<script setup>
  import { useInventoryStore } from './stores/inventory'
  import { useSettingsStore } from './stores/settings'
  import { postNUI, securePostNUI } from './utils/nui'
  import { ref, onMounted, onUnmounted, watch } from 'vue'
  const inventory = useInventoryStore()
  const settings = useSettingsStore()

  var fallbackImage = new URL('./assets/unknown-image.png', import.meta.url).href
  var popSound = new Audio(new URL('./assets/ui-pop.mp3', import.meta.url).href)
  popSound.volume = 0.08

  function playPopSound() {
    if (!settings.soundEffects) return
    popSound.currentTime = 0
    popSound.play().catch(function() {})
  }

  function getItemImage(name) {
    return '../items/' + name + '.png'
  }

  function onImgError(e) {
    e.target.src = fallbackImage
  }

  function getAsset(filename) {
    return new URL(`./assets/${filename}`, import.meta.url).href
  }

  function slotCount(item) {
    if (item.type === 'item_weapon') return '1x'
    if (item.type === 'item_money' || item.type === 'item_gold') return formatCurrencyAmount(item.count)
    return Math.floor(Number(item.count) || 0) + 'x'
  }

  function slotWeight(item) {
    var w = item.weight || 0
    var c = item.type === 'item_weapon' ? 1 : item.count
    return (w * c).toFixed(2)
  }

  function formatCurrencyAmount(value) {
    return (Number(value) || 0).toFixed(2)
  }

  function isCurrencyItem(item) {
    return item && (item.type === 'item_money' || item.type === 'item_gold')
  }

  function isEquippedWeapon(item) {
    return item && item.type === 'item_weapon' && (item.used || item.used2)
  }

  function getTransferAmount(item) {
    var amount = Number(transferAmount.value)
    var max = Number(item.count) || 0
    if (!amount || amount <= 0) amount = max
    if (amount > max) amount = max
    if (isCurrencyItem(item)) return Math.floor(amount * 100) / 100
    return Math.max(1, Math.floor(amount))
  }

  function normalizedMetadata(item) {
    var metadata = item && item.metadata ? item.metadata : {}
    var keys = Object.keys(metadata).sort()
    var normalized = {}
    for (var i = 0; i < keys.length; i++) normalized[keys[i]] = metadata[keys[i]]
    return JSON.stringify(normalized)
  }

  function canStackItems(a, b) {
    if (!a || !b) return false
    if (a.name !== b.name || a.type === 'item_weapon' || b.type === 'item_weapon') return false
    if (normalizedMetadata(a) !== normalizedMetadata(b)) return false
    var aMax = Number(a.maxDegradation) || 0
    var bMax = Number(b.maxDegradation) || 0
    if (aMax !== bMax) return false
    if (aMax > 0) return Number(a.percentage) === Number(b.percentage) && Number(a.degradation) === Number(b.degradation)
    return true
  }

  const contextMenu = ref({ show: false, x: 0, y: 0, item: null })

  // Search
  const searchQuery = ref('')
  const searchMatchSlots = ref([])
  var searchBlinkInterval = null
  var searchBlinkOn = ref(true)

  function onSearchInput() {
    var q = searchQuery.value.toLowerCase().trim()
    if (!q) {
      searchMatchSlots.value = []
      if (searchBlinkInterval) { clearInterval(searchBlinkInterval); searchBlinkInterval = null }
      searchBlinkOn.value = true
      return
    }
    var matches = []
    var totalSlots = inventory.LuaConfig.PlayerInventorySlots || 25
    for (var i = 1; i <= totalSlots; i++) {
      var item = inventory.getItemAtSlot(i)
      if (item && item.label && item.label.toLowerCase().indexOf(q) !== -1) {
        matches.push(i)
      }
    }
    searchMatchSlots.value = matches

    // Blink effect
    if (searchBlinkInterval) clearInterval(searchBlinkInterval)
    searchBlinkOn.value = true
    searchBlinkInterval = setInterval(function() {
      searchBlinkOn.value = !searchBlinkOn.value
    }, 400)

    // Scroll to first match
    if (matches.length > 0) {
      var slotEl = document.getElementById('player-slot-' + matches[0])
      if (slotEl) slotEl.scrollIntoView({ behavior: 'smooth', block: 'center' })
    }
  }

  function isSearchMatch(slotIndex) {
    return searchMatchSlots.value.indexOf(slotIndex) !== -1
  }

  // Ammo give prompt
  const ammoPrompt = ref({ show: false, ammoType: '', ammoLabel: '', amount: 1 })

  function getAmmoList() {
    var list = []
    var ammo = inventory.allplayerammo
    var labels = inventory.ammolabels
    for (var key in ammo) {
      if (ammo[key] > 0) {
        list.push({ key: key, label: labels[key] || key, count: ammo[key] })
      }
    }
    return list
  }

  function onAmmoClick(ammoType, ammoLabel) {
    contextMenu.value.show = false
    ammoPrompt.value = { show: true, ammoType: ammoType, ammoLabel: ammoLabel, amount: 1 }
  }

  function onAmmoPromptConfirm() {
    var amount = parseInt(ammoPrompt.value.amount)
    if (!amount || amount <= 0) return
    ammoPrompt.value.show = false
    postNUI('GetNearPlayers', { type: 'item_ammo', what: 'give', item: ammoPrompt.value.ammoType, count: amount }).catch(function(){})
  }

  function onPlayerSelect(playerId) {
    inventory.showPlayerSelect = false
    var data = inventory.pendingGiveData
    if (!data) return
    securePostNUI('GiveItem', { player: playerId, data: data }).catch(function(){})
    inventory.pendingGiveData = null
  }

  function onPlayerSelectClose() {
    inventory.showPlayerSelect = false
    inventory.pendingGiveData = null
  }

  function onSlotRightClick(e, slotIndex) {
    const item = inventory.getItemAtSlot(slotIndex)
    if (!item) return
    e.preventDefault()
    contextMenu.value = { show: true, x: e.clientX, y: e.clientY, item }
  }

  function onSlotDoubleClick(slotIndex) {
    if (dragTimer) { clearTimeout(dragTimer); dragTimer = null }
    dragStartPos = null
    dragFrom.value = null
    dragSource.value = null
    dragGhost.value.show = false
    if (!settings.doubleClickToUse) return
    var item = inventory.getItemAtSlot(slotIndex)
    if (!item) return
    if (item.type === 'item_money' || item.type === 'item_gold') return
    if (item.type === 'item_weapon' && (item.used || item.used2)) {
      postNUI('UnequipWeapon', { item: item.name, id: item.id })
    } else {
      var useAmt = getTransferAmount(item)
      postNUI('UseItem', { item: item.name, type: item.type, hash: item.hash, amount: useAmt, id: item.id })
    }
  }

  const dragFrom = ref(null)
  const dragSource = ref(null)
  const dragGhost = ref({ show: false, x: 0, y: 0, item: null })
  const transferAmount = ref(0)
  var dragTimer = null
  var dragStartPos = null

  // Reset transferAmount when inventory opens/closes
  watch(() => inventory.isVisible, function() {
    transferAmount.value = 0
  })

  function onSlotMouseDown(e, slotIndex) {
    var item = inventory.getItemAtSlot(slotIndex)
    if (!item) return
    if (e.button !== 0) return
    e.preventDefault()
    dragStartPos = { x: e.clientX, y: e.clientY, slot: slotIndex, item: item, source: 'player' }
    dragTimer = setTimeout(function() {
      if (dragStartPos) {
        dragFrom.value = dragStartPos.slot
        dragSource.value = dragStartPos.source
        dragGhost.value = { show: true, x: dragStartPos.x, y: dragStartPos.y, item: dragStartPos.item }
        dragStartPos = null
      }
    }, 150)
  }

  function onMouseMove(e) {
    if (!dragGhost.value.show) return
    dragGhost.value.x = e.clientX
    dragGhost.value.y = e.clientY
  }

  function onSlotMouseUp(toSlot) {
    if (dragFrom.value === null) return
    if (dragSource.value === 'dropzone') {
      var dropItem = inventory.getDropZoneItemAtSlot(dragFrom.value)
      if (dropItem) {
        // Block if target slot has different item
        var targetPlayerItem = inventory.getItemAtSlot(toSlot)
        if (targetPlayerItem && !canStackItems(dropItem, targetPlayerItem)) { dragFrom.value = null; dragSource.value = null; dragGhost.value.show = false; return }

        var amount = getTransferAmount(Object.assign({}, dropItem, { count: dropItem.amount }))

        postNUI('PickupFromDrop', {
          dropId: inventory.nearbyDropId,
          fromSlot: dragFrom.value,
          targetSlot: toSlot,
          amount: amount,
          name: dropItem.name,
          type: dropItem.type,
          isMoney: dropItem.isMoney || false,
          isGold: dropItem.isGold || false,
          uuid: dropItem.uuid,
          uids: dropItem.uids,
        })
        playPopSound()
      }
      dragFrom.value = null
      dragSource.value = null
      dragGhost.value.show = false
      return
    }
    // Second inventory → Player (TakeFrom)
    if (dragSource.value === 'second') {
      var secItem = inventory.getSecondItemAtSlot(dragFrom.value)
      if (secItem) {
        var targetPlayerItem2 = inventory.getItemAtSlot(toSlot)
        // Steal: swap when different items
        if (inventory.invType === 'steal' && targetPlayerItem2 && !canStackItems(secItem, targetPlayerItem2)) {
          postNUI('StealSwapBetween', { playerSlot: toSlot, stealSlot: dragFrom.value })
          playPopSound()
        } else if (targetPlayerItem2 && !canStackItems(secItem, targetPlayerItem2)) {
          dragFrom.value = null; dragSource.value = null; dragGhost.value.show = false; return
        } else {
          var type = inventory.invType
          var mapping = takeFromActions[type]
          if (mapping) {
            var amount = getTransferAmount(secItem)
            var payload = { item: secItem, type: secItem.type, number: amount, targetSlot: toSlot }
            payload[mapping.key] = mapping.getId()
            postNUI(mapping.action, payload)
            playPopSound()
          }
        }
      }
      dragFrom.value = null
      dragSource.value = null
      dragGhost.value.show = false
      return
    }
    // Craft → Player
    if (dragSource.value === 'craft') {
      var craftItem = inventory.getCraftItemAtSlot(dragFrom.value)
      if (craftItem) {
        var targetPlayerItem3 = inventory.getItemAtSlot(toSlot)
        if (targetPlayerItem3 && !canStackItems(craftItem, targetPlayerItem3)) { dragFrom.value = null; dragSource.value = null; dragGhost.value.show = false; return }
        var amount = getTransferAmount(craftItem)
        postNUI('CraftRemoveItem', { fromSlot: dragFrom.value, amount: amount, targetSlot: toSlot })
        playPopSound()
      }
      dragFrom.value = null
      dragSource.value = null
      dragGhost.value.show = false
      return
    }
    if (dragFrom.value !== toSlot) {
      var fromItem = inventory.getItemAtSlot(dragFrom.value)
      var amount = fromItem ? getTransferAmount(fromItem) : 0
      inventory.swapSlots(dragFrom.value, toSlot, amount > 0 ? amount : null)
      playPopSound()
    }
    dragFrom.value = null
    dragSource.value = null
    dragGhost.value.show = false
  }

  function onDropZoneMouseDown(e, slotIndex) {
    var item = inventory.getDropZoneItemAtSlot(slotIndex)
    if (!item) return
    if (e.button !== 0) return
    e.preventDefault()
    dragStartPos = { x: e.clientX, y: e.clientY, slot: slotIndex, item: item, source: 'dropzone' }
    dragTimer = setTimeout(function() {
      if (dragStartPos) {
        dragFrom.value = dragStartPos.slot
        dragSource.value = dragStartPos.source
        dragGhost.value = { show: true, x: dragStartPos.x, y: dragStartPos.y, item: dragStartPos.item }
        dragStartPos = null
      }
    }, 150)
  }

  function onDropSlotMouseUp(toSlot) {
    if (dragFrom.value === null) return
    if (dragSource.value === 'player') {
      var item = inventory.getItemAtSlot(dragFrom.value)
      if (item) {
        if (isEquippedWeapon(item)) { dragFrom.value = null; dragSource.value = null; dragGhost.value.show = false; return }
        // Block if target slot has different item
        var targetDropItem = inventory.getDropZoneItemAtSlot(toSlot)
        if (targetDropItem && !canStackItems(item, targetDropItem)) { dragFrom.value = null; dragSource.value = null; dragGhost.value.show = false; return }

        var amount = getTransferAmount(item)

        // Check drop weight limit
        var dropConfig = inventory.LuaConfig.DropInventory
        if (dropConfig && dropConfig.MaxWeight > 0) {
          var itemWeight = (item.weight || 0) * amount
          if (inventory.dropCurrentWeight + itemWeight > dropConfig.MaxWeight) return
        }

        securePostNUI('DropItem', {
          item: item.name,
          id: item.id,
          number: amount,
          type: item.type,
          metadata: item.metadata,
          degradation: item.degradation,
          targetSlot: toSlot,
        })
        playPopSound()
      }
    } else if (dragSource.value === 'dropzone' && dragFrom.value !== toSlot) {
      var fromItem = inventory.getDropZoneItemAtSlot(dragFrom.value)
      var amount = fromItem ? getTransferAmount(Object.assign({}, fromItem, { count: fromItem.amount })) : 0
      inventory.swapDropSlots(dragFrom.value, toSlot, amount > 0 ? amount : null)
      playPopSound()
    }
    dragFrom.value = null
    dragSource.value = null
    dragGhost.value.show = false
  }

  function onDropGive() {
    if (dragFrom.value === null) return
    if (dragSource.value !== 'player') { dragFrom.value = null; dragSource.value = null; dragGhost.value.show = false; return }
    var item = inventory.getItemAtSlot(dragFrom.value)
    if (!item) { dragFrom.value = null; dragGhost.value.show = false; return }
    if (isEquippedWeapon(item)) { dragFrom.value = null; dragSource.value = null; dragGhost.value.show = false; return }
    if (item.locked && item.type !== 'item_money' && item.type !== 'item_gold') { dragFrom.value = null; dragSource.value = null; dragGhost.value.show = false; return }

    var amount = getTransferAmount(item)

    var giveType = item.type
    var giveItem = item.name
    var giveCount = amount
    var giveId = item.id
    var giveHash = item.hash || 1

    // For money/gold use special types
    if (item.type === 'item_money') giveItem = 'money'
    if (item.type === 'item_gold') giveItem = 'gold'

    postNUI('GetNearPlayers', { type: giveType, what: 'give', item: giveItem, count: giveCount, id: giveId, hash: giveHash }).catch(function(){})
    playPopSound()
    dragFrom.value = null
    dragSource.value = null
    dragGhost.value.show = false
  }

  function onDropUse() {
    if (dragFrom.value === null) return
    if (dragSource.value !== 'player') { dragFrom.value = null; dragSource.value = null; dragGhost.value.show = false; return }
    var item = inventory.getItemAtSlot(dragFrom.value)
    if (!item) { dragFrom.value = null; dragGhost.value.show = false; return }
    if (item.type === 'item_money' || item.type === 'item_gold') { dragFrom.value = null; dragSource.value = null; dragGhost.value.show = false; return }
    if (item.type === 'item_weapon' && (item.used || item.used2)) {
      postNUI('UnequipWeapon', { item: item.name, id: item.id })
    } else {
      var useAmt = getTransferAmount(item)
      postNUI('UseItem', { item: item.name, type: item.type, hash: item.hash, amount: useAmt, id: item.id })
    }
    playPopSound()
    dragFrom.value = null
    dragGhost.value.show = false
  }

  function onMouseUp() {
    if (dragTimer) { clearTimeout(dragTimer); dragTimer = null }
    dragStartPos = null
    if (dragGhost.value.show) {
      dragFrom.value = null
      dragSource.value = null
      dragGhost.value.show = false
    }
  }

  // Craft slot handlers
  function onCraftSlotMouseDown(e, slotIndex) {
    if (inventory.craftingInProgress) return
    var item = inventory.getCraftItemAtSlot(slotIndex)
    if (!item) return
    if (e.button !== 0) return
    e.preventDefault()
    dragStartPos = { x: e.clientX, y: e.clientY, slot: slotIndex, item: item, source: 'craft' }
    dragTimer = setTimeout(function() {
      if (dragStartPos) {
        dragFrom.value = dragStartPos.slot
        dragSource.value = dragStartPos.source
        dragGhost.value = { show: true, x: dragStartPos.x, y: dragStartPos.y, item: dragStartPos.item }
        dragStartPos = null
      }
    }, 150)
  }

  function onCraftSlotMouseUp(toSlot) {
    if (dragFrom.value === null) return
    if (inventory.craftingInProgress) { dragFrom.value = null; dragSource.value = null; dragGhost.value.show = false; return }
    // Player → Craft
    if (dragSource.value === 'player') {
      var item = inventory.getItemAtSlot(dragFrom.value)
      if (item) {
        if (isEquippedWeapon(item)) { dragFrom.value = null; dragSource.value = null; dragGhost.value.show = false; return }
        var targetCraftItem = inventory.getCraftItemAtSlot(toSlot)
        if (targetCraftItem && !canStackItems(item, targetCraftItem)) { dragFrom.value = null; dragSource.value = null; dragGhost.value.show = false; return }
        var amount = getTransferAmount(item)
        postNUI('CraftAddItem', { itemId: item.id, amount: amount, targetSlot: toSlot })
        playPopSound()
      }
    // Craft → Craft (swap/merge/split)
    } else if (dragSource.value === 'craft' && dragFrom.value !== toSlot) {
      var fromItem = inventory.getCraftItemAtSlot(dragFrom.value)
      var toItem = inventory.getCraftItemAtSlot(toSlot)
      if (fromItem) {
        var amount = getTransferAmount(fromItem)
        if (canStackItems(fromItem, toItem)) {
          postNUI('CraftMergeSlot', { fromSlot: dragFrom.value, toSlot: toSlot, amount: amount || fromItem.count })
        } else if (!toItem && amount > 0 && amount < fromItem.count) {
          postNUI('CraftSplitSlot', { fromSlot: dragFrom.value, toSlot: toSlot, amount: amount })
        } else {
          postNUI('CraftSwapSlot', { fromSlot: dragFrom.value, toSlot: toSlot })
        }
        playPopSound()
      }
    }
    dragFrom.value = null
    dragSource.value = null
    dragGhost.value.show = false
  }

  function closeContextMenu() {
    contextMenu.value.show = false
  }

  const reservedMetaKeys = ['label', 'description', 'image', 'weight', 'tooltip', 'context', 'orgdescription', 'lumberdurability']

  function isReservedMeta(key) {
    return reservedMetaKeys.indexOf(key) !== -1
  }

  function hasItemInfo(item) {
    if (item.serial_number) return true
    if (item.type === 'item_weapon') return true
    if (item.maxDegradation > 0) return true
    if (item.metadata) {
      for (var key in item.metadata) {
        if (!isReservedMeta(key)) return true
      }
    }
    return false
  }

  function getItemDesc(item) {
    return item.metadata?.description || item.custom_desc || item.desc || ''
  }

  function getDegradation(item) {
    if (!item.maxDegradation || item.maxDegradation === 0) return 100
    if (item.percentage != null) return item.percentage
    var maxSec = item.maxDegradation * 60
    var elapsed = inventory.TIME_NOW - item.degradation
    return Math.max(0, ((maxSec - elapsed) / maxSec) * 100)
  }

  function getDegradationColor(pct) {
    if (pct < 15) return '#ef4444'
    if (pct < 40) return '#f97316'
    if (pct < 70) return '#eab308'
    return '#4a9e6b'
  }

  function getWeaponComponents(item) {
    if (!item || item.type !== 'item_weapon' || !item.comps || !item.comps.length) return []
    return item.comps
  }

  function onKeyDown(e) {
    if (e.key === 'Escape' || e.key === 'F1') {
      if (inventory.isVisible) {
        inventory.hide()
        searchQuery.value = ''
        searchMatchSlots.value = []
        if (searchBlinkInterval) { clearInterval(searchBlinkInterval); searchBlinkInterval = null }
        searchBlinkOn.value = true
      }
    }
  }

  onMounted(() => {
    document.addEventListener('click', closeContextMenu)
    document.addEventListener('keydown', onKeyDown)
    document.addEventListener('mousemove', onMouseMove)
    document.addEventListener('mouseup', onMouseUp)
  })
  onUnmounted(() => {
    document.removeEventListener('click', closeContextMenu)
    document.removeEventListener('keydown', onKeyDown)
    document.removeEventListener('mousemove', onMouseMove)
    document.removeEventListener('mouseup', onMouseUp)
  })

  const clothingSlots = ref([
    { id: 1,  label: 'Hat',      icon: 'hat-icon.png',      param: 'hat',      x: 28, y: 12,  rotate: 0,    lineSide: 'right' },
    { id: 2,  label: 'Mask',     icon: 'mask-icon.png',     param: 'mask',     x: 69, y: 18,  rotate: 0,    lineSide: 'left' },
    { id: 3,  label: 'Neckwear', icon: 'neckwear-icon.png', param: 'neckwear', x: 33, y: 22,  rotate: 0,    lineSide: 'right' },
    { id: 4,  label: 'Shirt',    icon: 'shirt-icon.png',    param: 'shirt',    x: 33, y: 40,  rotate: 0,    lineSide: 'right' },
    { id: 5,  label: 'Vest',     icon: 'vest-icon.png',     param: 'vest',     x: 30, y: 31,  rotate: 0,    lineSide: 'right' },
    { id: 6,  label: 'Poncho',   icon: 'poncho-icon.png',   param: 'poncho',   x: 74, y: 28,  rotate: 0,    lineSide: 'left' },
    { id: 7,  label: 'Coat',     icon: 'coat-icon.png',     param: 'coat',     x: 70, y: 40,  rotate: 0,    lineSide: 'left' },
    { id: 8,  label: 'Belt',     icon: 'belt-icon.png',     param: 'belt',     x: 35, y: 52,  rotate: -35,  lineSide: 'right' },
    { id: 9,  label: 'Sleeves',  icon: 'sleeves-icon.png',  param: 'sleeves',  x: 77, y: 50,  rotate: 35,   lineSide: 'left' },
    { id: 10, label: 'Boots',    icon: 'boots-icon.png',    param: 'boots',    x: 22, y: 84,  rotate: 0,    lineSide: 'right' },
    { id: 11, label: 'Pant',     icon: 'pant-icon.png',     param: 'ccoat',    x: 69, y: 70,  rotate: 40,   lineSide: 'left' },
    { id: 12, label: 'Gloves',   icon: 'glove-icon.png',    param: 'glove',   x: 14, y: 48,  rotate: 0,    lineSide: 'right' },
  ])

  // Second inventory transfer mappings (same as old UI)
  var moveToActions = {
    custom: { action: 'MoveToCustom', key: 'id', getId: function() { return inventory.customId } },
    player: { action: 'MoveToPlayer', key: 'player', getId: function() { return inventory.playerId } },
    horse: { action: 'MoveToHorse', key: 'horse', getId: function() { return inventory.horseid } },
    cart: { action: 'MoveToCart', key: 'wagon', getId: function() { return inventory.wagonid } },
    house: { action: 'MoveToHouse', key: 'house', getId: function() { return inventory.houseId } },
    hideout: { action: 'MoveToHideout', key: 'hideout', getId: function() { return inventory.hideoutId } },
    bank: { action: 'MoveToBank', key: 'bank', getId: function() { return inventory.bankId } },
    clan: { action: 'MoveToClan', key: 'clan', getId: function() { return inventory.clanid } },
    steal: { action: 'MoveTosteal', key: 'steal', getId: function() { return inventory.stealid } },
    Container: { action: 'MoveToContainer', key: 'Container', getId: function() { return inventory.Containerid } },
  }

  var takeFromActions = {
    custom: { action: 'TakeFromCustom', key: 'id', getId: function() { return inventory.customId } },
    player: { action: 'TakeFromPlayer', key: 'player', getId: function() { return inventory.playerId } },
    horse: { action: 'TakeFromHorse', key: 'horse', getId: function() { return inventory.horseid } },
    cart: { action: 'TakeFromCart', key: 'wagon', getId: function() { return inventory.wagonid } },
    house: { action: 'TakeFromHouse', key: 'house', getId: function() { return inventory.houseId } },
    hideout: { action: 'TakeFromHideout', key: 'hideout', getId: function() { return inventory.hideoutId } },
    bank: { action: 'TakeFromBank', key: 'bank', getId: function() { return inventory.bankId } },
    clan: { action: 'TakeFromClan', key: 'clan', getId: function() { return inventory.clanid } },
    steal: { action: 'TakeFromsteal', key: 'steal', getId: function() { return inventory.stealid } },
    Container: { action: 'TakeFromContainer', key: 'Container', getId: function() { return inventory.Containerid } },
  }

  function onSecondMouseDown(e, slotIndex) {
    var item = inventory.getSecondItemAtSlot(slotIndex)
    if (!item) return
    if (e.button !== 0) return
    e.preventDefault()
    dragStartPos = { x: e.clientX, y: e.clientY, slot: slotIndex, item: item, source: 'second' }
    dragTimer = setTimeout(function() {
      if (dragStartPos) {
        dragFrom.value = dragStartPos.slot
        dragSource.value = dragStartPos.source
        dragGhost.value = { show: true, x: dragStartPos.x, y: dragStartPos.y, item: dragStartPos.item }
        dragStartPos = null
      }
    }, 150)
  }

  function onSecondMouseUp(toSlot) {
    if (dragFrom.value === null) return
    // Player → Second inventory (MoveTo)
    if (dragSource.value === 'player') {
      var item = inventory.getItemAtSlot(dragFrom.value)
      if (item) {
        if (isEquippedWeapon(item)) { dragFrom.value = null; dragSource.value = null; dragGhost.value.show = false; return }
        var targetSecItem = inventory.getSecondItemAtSlot(toSlot)
        // Steal: swap when different items
        if (inventory.invType === 'steal' && targetSecItem && !canStackItems(item, targetSecItem)) {
          postNUI('StealSwapBetween', { playerSlot: dragFrom.value, stealSlot: toSlot })
          playPopSound()
        } else if (targetSecItem && !canStackItems(item, targetSecItem)) {
          dragFrom.value = null; dragSource.value = null; dragGhost.value.show = false; return
        } else {
          var type = inventory.invType
          var mapping = moveToActions[type]
          if (mapping) {
            var amount = getTransferAmount(item)
            var payload = { item: item, type: item.type, number: amount, targetSlot: toSlot }
            payload[mapping.key] = mapping.getId()
            postNUI(mapping.action, payload)
            playPopSound()
          }
        }
      }
    // Second → Second (swap/merge/split within second inventory)
    } else if (dragSource.value === 'second' && dragFrom.value !== toSlot) {
      var fromItem = inventory.getSecondItemAtSlot(dragFrom.value)
      var amount = fromItem ? getTransferAmount(fromItem) : 0
      if (inventory.invType === 'steal') {
        inventory.swapStealSlots(dragFrom.value, toSlot, amount > 0 ? amount : null)
      } else {
        inventory.swapSecondSlots(dragFrom.value, toSlot, amount > 0 ? amount : null)
      }
      playPopSound()
    }
    dragFrom.value = null
    dragSource.value = null
    dragGhost.value.show = false
  }

  function onClothingClick(slot) {
    postNUI('ChangeClothing', JSON.stringify(slot.param))
  }
</script>

<template>
  <div class="w-screen h-screen overflow-hidden p-20 flex flex-col " style="background-size: 100% 100%;">
    <!-- Drag Ghost -->
      <div v-if="dragGhost.show && dragGhost.item" class="fixed z-[100] pointer-events-none w-[4vw] h-[4vw] opacity-80" :style="{ left: (dragGhost.x - 30) + 'px', top: (dragGhost.y - 30) + 'px' }">
        <img :src="getItemImage(dragGhost.item.name)" @error="onImgError" class="w-full h-full object-contain">
      </div>
    <!-- Background Effect Overlay -->
      <Transition name="fade">
        <div v-if="inventory.isVisible" class="fixed inset-0 z-10 bg-[url(./assets/background-effect.png)] pointer-events-none" style="background-size: 100% 100%;"></div>
      </Transition>
    <!--  Inventory Main -->
      <Transition name="fade">
      <div v-if="inventory.isVisible" class="w-full h-full z-20 flex justify-between items-center">
          <div class="w-[28%] h-[80%] p-6 flex flex-col justify-between items-center  bg-[url(./assets/inventory-background.png)]" style="background-size: 100% 100%;">
              <div height="9%" class="p-2 flex justify-between items-center h-[9%] w-full bg-[url(./assets/header-background.png)]" style="background-size: 100% 100%;">
                  <p class="text-xl">{{ inventory.LuaConfig.ShowCharacterNameInTitle && inventory.charName ? inventory.charName + ' - ' + inventory.charId : 'Inventory - ' + inventory.charId }}</p>
                  <div class="w-[2vw] h-[2vw]  flex justify-center items-center rounded-md bg-black/10">
                      <img src="./assets/inventory-icon.png">
                  </div>
              </div>
              <div class="w-full h-[15%]  flex flex-col justify-between">
                  <div class="flex justify-between  ">
                      <div height="35px" width="30%" class="p-2 flex justify-between items-center h-[35px] w-[30%] bg-[url(./assets/info-background.png)]" style="background-size: 100% 100%;">
                          <img src="./assets/gold-icon.png">
                          <p>{{ inventory.gold.toFixed(2) }}</p>
                      </div>
                      <div height="35px" width="30%" class="p-2 flex justify-between items-center h-[35px] w-[30%] bg-[url(./assets/info-background.png)]" style="background-size: 100% 100%;">
                          <img src="./assets/cash-icon.png">
                          <p>{{ inventory.money.toFixed(2) }}</p>
                      </div>
                      <div class="w-[38%] h-[35px] flex flex-col justify-between items-center  gap-1">
                          <div class="weight-bar">
                            <div class="weight-bar-fill" :style="{ width: inventory.maxWeight ? (inventory.currentWeight / inventory.maxWeight * 100) + '%' : '0%' }"></div>
                          </div>
                          <div class="flex  w-full justify-between items-center">
                              <p class="text-sm text-[#BEB592]">Weight</p>
                              <p class="text-sm text-[#BEB592]"><span class="font-semibold">{{ inventory.currentWeight }}</span>/{{ inventory.maxWeight }}{{ inventory.LuaConfig.WeightMeasure || 'kg' }}</p>
                          </div>
                          
                      </div>
                  </div>
                  <div class="p-2 flex items-center gap-2 w-full bg-[url(./assets/search-background.png)]" style="background-size: 100% 100%;">
                      <img src="./assets/search-icon.png">
                      <input type="text" v-model="searchQuery" @input="onSearchInput" class="w-[70%] h-full text-[#000000]" placeholder="Search any item...">
                  </div>
              </div>
              <div class="w-full h-[65%] grid grid-cols-5 gap-1.5 content-start overflow-y-auto">
                  <div v-for="i in (inventory.LuaConfig.PlayerInventorySlots || 25)" :key="i" :id="'player-slot-' + i" @mousedown="onSlotMouseDown($event, i)" @mouseup="onSlotMouseUp(i)" @contextmenu="onSlotRightClick($event, i)" @dblclick="onSlotDoubleClick(i)" class="aspect-square bg-white/[0.08] rounded transition-all hover:opacity-70 p-1 relative flex flex-col items-center justify-center" :class="{ 'opacity-30': dragFrom === i && dragSource === 'player' }" :style="isSearchMatch(i) ? { opacity: searchBlinkOn ? 1 : 0.3, transition: 'opacity 0.3s' } : {}">
                      <template v-if="inventory.getItemAtSlot(i)">
                          <span class="absolute top-0.5 right-1 text-[10px] text-white/40">{{ slotCount(inventory.getItemAtSlot(i)) }}</span>
                          <span class="absolute top-0.5 left-1 text-[10px] text-white/40">{{ slotWeight(inventory.getItemAtSlot(i)) }}kg</span>
                          <img :src="getItemImage(inventory.getItemAtSlot(i).name)" @error="onImgError" class="absolute inset-0 m-auto max-w-[40%] max-h-[60%] object-contain">
                          <svg v-if="inventory.getItemAtSlot(i).type === 'item_weapon' && inventory.getItemAtSlot(i).durability != null" class="absolute left-1 top-1/2 -translate-y-1/2" width="12" height="12" viewBox="0 0 36 36">
                            <circle cx="18" cy="18" r="15" fill="none" stroke="rgba(0,0,0,0.3)" stroke-width="4"></circle>
                            <circle cx="18" cy="18" r="15" fill="none" :stroke="getDegradationColor(inventory.getItemAtSlot(i).durability)" stroke-width="4" stroke-linecap="round" :stroke-dasharray="(inventory.getItemAtSlot(i).durability / 100 * 94.2) + ' 94.2'" transform="rotate(-90 18 18)"></circle>
                          </svg>
                          <span v-if="isEquippedWeapon(inventory.getItemAtSlot(i))" class="absolute left-1 text-[12px] font-semibold leading-none text-[#2fd06c] pointer-events-none" style="top: calc(50% - 22px); text-shadow: 0 1px 2px rgba(0,0,0,0.65);">E</span>
                          <p class="absolute bottom-0.5 left-0 right-0 text-center text-[10px] text-white/70 truncate px-0.5">{{ inventory.getItemAtSlot(i).label }}</p>
                      </template>
                      <template v-else>
                          <span class="absolute top-0.5 right-1 text-[10px] text-white/40">{{ i }}</span>
                      </template>
                  </div>
              </div>
              <div class="w-full h-[8%]  flex justify-between items-end">
                  <div @click="inventory.hide()" class="w-[32%] h-[70%] flex justify-between items-center p-2 transition-all hover:opacity-70 cursor-pointer bg-[url(./assets/bottom-menu-background.png)]" style="background-size: 100% 100%;">
                    <img src="./assets/close-icon.png">
                    <p class="text-xs">Close Inventory</p>
                  </div>
                  <div @click="inventory.secondInventoryType = inventory.secondInventoryType === 'clothing' ? (inventory.invType === 'main' ? 'drop' : 'inventory') : 'clothing'" class="w-[32%] h-[70%] flex justify-between items-center p-2 transition-all hover:opacity-70 cursor-pointer bg-[url(./assets/bottom-menu-background.png)]" style="background-size: 100% 100%;">
                    <img src="./assets/clothing-icon.png">
                    <p class="text-xs">Clothing Menu</p>
                  </div>
                  <div @click="settings.toggle()" class="w-[32%] h-[70%] flex justify-between items-center p-2 transition-all hover:opacity-70 cursor-pointer bg-[url(./assets/bottom-menu-background.png)]" style="background-size: 100% 100%;">
                    <img src="./assets/settings-icon.png">
                    <p class="text-xs">Settings</p>
                  </div>
              </div>
          </div>
          <div class="w-[30%] h-[80%] relative flex flex-col justify-center items-center">
              <div class="w-[9vw] h-[5vh]  flex justify-center items-center transition-all hover:opacity-70 bg-[url(./assets/amount-background.png)]" style="background-size: 100% 100%;">
                  <input type="number" v-model.number="transferAmount" min="0.01" step="any" @keydown="$event.key === '-' || $event.key === 'e' ? $event.preventDefault() : null" class="w-full h-full text-center text-xl text-[#BEB592]" placeholder="1">
              </div>
              <div @mouseup="onDropUse" class="w-[9vw] h-[5vh] mt-2 flex justify-center text-xl text-[#BEB592] items-center transition-all cursor-pointer bg-[url(./assets/buttons-background.png)]" :style="{ opacity: dragFrom !== null && dragSource === 'player' ? 1 : 0.4, backgroundSize: '100% 100%' }">
                  Use
              </div>
              <div @mouseup="onDropGive" class="w-[9vw] h-[5vh] flex justify-center text-xl text-[#BEB592] items-center transition-all cursor-pointer bg-[url(./assets/buttons-background.png)]" :style="{ opacity: dragFrom !== null && dragSource === 'player' ? 1 : 0.4, backgroundSize: '100% 100%' }">
                  Give
              </div>
              <!-- settings panel -->
              <Transition name="fade">
              <div v-if="settings.isOpen" class="absolute p-6 bottom-0 w-[80%] h-[25vh] bg-[url(./assets/settings-background.png)] flex flex-col gap-1" style="background-size: 100% 100%;">
                <div class="flex justify-between items-center p-2 h-[25%] w-full bg-[url(./assets/settings-item-background.png)]" style="background-size: 100% 100%;">
                  <div class="flex items-center gap-2">
                    <div class="w-[1.75vw] h-[1.75vw] rounded-md bg-black/10 flex justify-center items-center">
                        <img src="./assets/sound-effects-icon.png">
                    </div>
                    <p>Enable Sound Effects</p>
                  </div>
                  <div @click="settings.soundEffects = !settings.soundEffects" class="w-[1.75vw] h-[1.75vw] bg-[url(./assets/toggle-background.png)] cursor-pointer hover:opacity-80 flex justify-center items-center" style="background-size: 100% 100%;">
                      <Transition name="scale"><img v-if="settings.soundEffects" src="./assets/toggled-icon.png"></Transition>
                  </div>
                </div>
                <!-- settings 2 -->
                <div class="flex justify-between items-center p-2 h-[25%] w-full bg-[url(./assets/settings-item-background.png)]" style="background-size: 100% 100%;">
                  <div class="flex items-center gap-2">
                    <div class="w-[1.75vw] h-[1.75vw] rounded-md bg-black/10 flex justify-center items-center">
                        <img src="./assets/square.png">
                    </div>
                    <p>Show Item Add/Remove Notifications</p>
                  </div>
                  <div @click="settings.showNotifications = !settings.showNotifications" class="w-[1.75vw] h-[1.75vw] bg-[url(./assets/toggle-background.png)] cursor-pointer hover:opacity-80 flex justify-center items-center" style="background-size: 100% 100%;">
                      <Transition name="scale"><img v-if="settings.showNotifications" src="./assets/toggled-icon.png"></Transition>
                  </div>
                </div>
                <!-- settings 3 -->
                <div class="flex justify-between items-center p-2 h-[25%] w-full bg-[url(./assets/settings-item-background.png)]" style="background-size: 100% 100%;">
                  <div class="flex items-center gap-2">
                    <div class="w-[1.75vw] h-[1.75vw] rounded-md bg-black/10 flex justify-center items-center">
                        <img src="./assets/notification-duration-icon.png">
                    </div>
                    <p>Notification Duration</p>
                  </div>
                  <div class="h-[1.5vw] flex gap-1 items-center">
                      <div class="w-[4vw] h-full bg-[url(./assets/ms-input-background.png)]" style="background-size: 100% 100%;">
                          <input type="number" v-model.number="settings.notificationDuration" class="w-full h-full text-center text-[#BEB592]" placeholder="3000">
                      </div>
                      <p class="text-xs text-[#4D4B4B]">ms</p>
                  </div>
                </div>
                <!-- settings 4 -->
                <div class="flex justify-between items-center p-2 h-[25%] w-full bg-[url(./assets/settings-item-background.png)]" style="background-size: 100% 100%;">
                  <div class="flex items-center gap-2">
                    <div class="w-[1.75vw] h-[1.75vw] rounded-md bg-black/10 flex justify-center items-center">
                        <img src="./assets/double-click-icon.png">
                    </div>
                    <p>Double Click to Use</p>
                  </div>
                  <div @click="settings.doubleClickToUse = !settings.doubleClickToUse" class="w-[1.75vw] h-[1.75vw] bg-[url(./assets/toggle-background.png)] cursor-pointer hover:opacity-80 flex justify-center items-center" style="background-size: 100% 100%;">
                      <Transition name="scale"><img v-if="settings.doubleClickToUse" src="./assets/toggled-icon.png"></Transition>
                  </div>
                </div>
              </div>
              </Transition>
              
          </div>
          <div class="w-[28%] h-[80%] p-6 flex flex-col justify-between items-center  bg-[url(./assets/inventory-background.png)]" style="background-size: 100% 100%;">
              <!-- Second Inventory: inventory -->
              <Transition name="fade" mode="out-in">
              <div v-if="inventory.secondInventoryType === 'inventory'" key="inventory" class="w-full h-full flex flex-col justify-between items-center">
                <div height="9%" class="p-2 flex justify-between items-center h-[9%] w-full bg-[url(./assets/header-background.png)]" style="background-size: 100% 100%;">
                  <p class="text-xl">{{ inventory.secondTitle }}</p>
                  <div class="w-[2vw] h-[2vw]  flex justify-center items-center rounded-md bg-black/10">
                      <img src="./assets/user-icon.png">
                  </div>
                </div>
                <div class="w-full h-[6vh] flex flex-col items-center justify-center gap-1">
                    <div class="weight-bar">
                      <div class="weight-bar-fill" :style="{ width: inventory.secondCapacity > 0 ? (inventory.secondCurrentCount / inventory.secondCapacity * 100) + '%' : '0%' }"></div>
                    </div>
                    <div class="w-full flex justify-between items-center">
                        <p class="text-sm text-[#BEB592]">{{ inventory.secondWeight ? 'Max Weight' : 'Item Limit' }}</p>
                        <p class="text-sm text-[#BEB592]"><span class="font-semibold">{{ inventory.secondCurrentCount }}</span>/{{ inventory.secondCapacity }}{{ inventory.secondWeight ? (inventory.LuaConfig.WeightMeasure || 'kg') : '' }}</p>
                    </div>
                </div>
                <div class="w-full h-[80%] grid grid-cols-5 gap-1.5 content-start overflow-y-auto">
                    <div v-for="i in 35" :key="i" @mousedown="onSecondMouseDown($event, i)" @mouseup="onSecondMouseUp(i)" class="aspect-square bg-white/[0.08] rounded transition-all hover:opacity-70 p-1 relative flex flex-col items-center justify-center" :class="{ 'opacity-30': dragFrom === i && dragSource === 'second' }">
                        <template v-if="inventory.getSecondItemAtSlot(i)">
                            <span class="absolute top-0.5 right-1 text-[10px] text-white/40">{{ slotCount(inventory.getSecondItemAtSlot(i)) }}</span>
                            <span class="absolute top-0.5 left-1 text-[10px] text-white/40">{{ slotWeight(inventory.getSecondItemAtSlot(i)) }}kg</span>
                            <img :src="getItemImage(inventory.getSecondItemAtSlot(i).name)" @error="onImgError" class="absolute inset-0 m-auto max-w-[40%] max-h-[60%] object-contain">
                            <svg v-if="inventory.getSecondItemAtSlot(i).type === 'item_weapon' && inventory.getSecondItemAtSlot(i).durability != null" class="absolute left-1 top-1/2 -translate-y-1/2" width="12" height="12" viewBox="0 0 36 36">
                              <circle cx="18" cy="18" r="15" fill="none" stroke="rgba(0,0,0,0.3)" stroke-width="4"></circle>
                              <circle cx="18" cy="18" r="15" fill="none" :stroke="getDegradationColor(inventory.getSecondItemAtSlot(i).durability)" stroke-width="4" stroke-linecap="round" :stroke-dasharray="(inventory.getSecondItemAtSlot(i).durability / 100 * 94.2) + ' 94.2'" transform="rotate(-90 18 18)"></circle>
                            </svg>
                            <p class="absolute bottom-0.5 left-0 right-0 text-center text-[10px] text-white/70 truncate px-0.5">{{ inventory.getSecondItemAtSlot(i).label }}</p>
                        </template>
                        <template v-else>
                            <span class="absolute top-0.5 right-1 text-[10px] text-white/40">{{ i }}</span>
                        </template>
                    </div>
                </div>
              </div>

              <!-- Second Inventory: craft -->
              <div v-else-if="inventory.secondInventoryType === 'craft'" key="craft" class="w-full h-full flex flex-col justify-between items-center">
                  <div class="p-2 flex justify-between items-center h-[9%] w-full bg-[url(./assets/header-background.png)]" style="background-size: 100% 100%;">
                    <p class="text-xl">Craft Inventory</p>
                    <div class="w-[2vw] h-[2vw] flex justify-center items-center rounded-md bg-black/10">
                        <img src="./assets/craft-icon.png">
                    </div>
                  </div>
                  <!-- Progress bar -->
                  <div class="w-full h-[6vh] flex flex-col items-center justify-center gap-1">
                    <div class="weight-bar">
                      <div class="weight-bar-fill" :style="{ width: inventory.craftProgress + '%' }"></div>
                    </div>
                    <div class="w-full flex justify-between items-center">
                        <p class="text-sm text-[#BEB592]">{{ inventory.craftingInProgress ? 'Crafting...' : 'Craft Progress' }}</p>
                        <span class="font-semibold text-[#BEB592]">{{ inventory.craftProgress.toFixed(0) }}%</span>
                    </div>
                    
                  </div>
                  <!-- Craft slots -->
                  <div class="w-full h-[30%] grid grid-cols-5 gap-1.5 content-start overflow-y-auto">
                    <div v-for="i in 20" :key="i" @mousedown="onCraftSlotMouseDown($event, i)" @mouseup="onCraftSlotMouseUp(i)" class="aspect-square rounded transition-all hover:opacity-70 p-1 relative flex flex-col items-center justify-center" :class="{ 'opacity-30': dragFrom === i && dragSource === 'craft' }" :style="{ backgroundColor: inventory.getCraftItemAtSlot(i) ? 'rgba(255,138,5,0.06)' : 'rgba(255,255,255,0.08)' }">
                        <template v-if="inventory.getCraftItemAtSlot(i)">
                            <span class="absolute top-0.5 right-1 text-[10px] text-white/40">{{ inventory.getCraftItemAtSlot(i).count }}x</span>
                            <span class="absolute top-0.5 left-1 text-[10px] text-white/40">{{ ((inventory.getCraftItemAtSlot(i).weight || 0) * inventory.getCraftItemAtSlot(i).count).toFixed(2) }}kg</span>
                            <img :src="getItemImage(inventory.getCraftItemAtSlot(i).name)" @error="onImgError" class="absolute inset-0 m-auto w-[40%] h-[60%] object-contain">
                            <svg v-if="inventory.getCraftItemAtSlot(i).type === 'item_weapon' && inventory.getCraftItemAtSlot(i).durability != null" class="absolute left-1 top-1/2 -translate-y-1/2" width="12" height="12" viewBox="0 0 36 36">
                              <circle cx="18" cy="18" r="15" fill="none" stroke="rgba(0,0,0,0.3)" stroke-width="4"></circle>
                              <circle cx="18" cy="18" r="15" fill="none" :stroke="getDegradationColor(inventory.getCraftItemAtSlot(i).durability)" stroke-width="4" stroke-linecap="round" :stroke-dasharray="(inventory.getCraftItemAtSlot(i).durability / 100 * 94.2) + ' 94.2'" transform="rotate(-90 18 18)"></circle>
                            </svg>
                            <p class="absolute bottom-0.5 left-0 right-0 text-center text-[10px] text-white/70 truncate px-0.5">{{ inventory.getCraftItemAtSlot(i).label }}</p>
                        </template>
                        <template v-else>
                            <span class="absolute top-0.5 right-1 text-[10px] text-white/40">{{ i }}</span>
                        </template>
                    </div>
                  </div>
                  <div class="w-full h-2 bg-[url(./assets/line.png)]" style="background-size: 100% 100%;"></div>
                  <!-- Recipe panel -->
                  <div class="w-full h-[37%] bg-white/10 rounded-md flex justify-center items-center p-5">
                    <!-- No recipe matched -->
                    <div v-if="!inventory.craftRecipe" class="text-center">
                      <p class="text-[#898888] text-sm">Prepare items to see progress!</p>
                    </div>
                    <!-- Recipe matched -->
                    <div v-else class="w-full h-full flex justify-between">
                      <!-- Reward -->
                      <div class="w-[30%] h-full flex flex-col justify-between">
                        <div class="gap-1">
                          <p class="text-[#CAA580] text-lg">{{ inventory.craftRecipe.rewardLabel }}</p>
                          <p class="text-[#898888] text-xs">To be crafted!</p>
                        </div>
                        <div class="w-[5vw] h-[5vw] rounded p-1 relative" style="background-color: rgba(255,138,5,0.06);">
                          <span class="absolute top-0.5 right-1 text-[10px] text-white/40">{{ inventory.craftRecipe.rewardAmount * inventory.craftAmount }}x</span>
                          <span class="absolute top-0.5 left-1 text-[10px] text-white/40">{{ ((inventory.craftRecipe.rewardWeight || 0) * inventory.craftRecipe.rewardAmount * inventory.craftAmount).toFixed(2) }}kg</span>
                          <img :src="getItemImage(inventory.craftRecipe.rewardName)" @error="onImgError" class="absolute inset-0 m-auto w-[40%] h-[60%] object-contain">
                          <p class="absolute bottom-0.5 left-0 right-0 text-center text-[10px] text-white/70 truncate px-0.5">{{ inventory.craftRecipe.rewardLabel }}</p>
                        </div>
                        <div class="w-[5vw] h-[2vw] flex justify-between items-center p-2 bg-[url(./assets/slider-background.png)]" style="background-size: 100% 100%;">
                          <div @click="!inventory.craftingInProgress && inventory.craftAmount > 1 ? inventory.craftAmount-- : null" class="w-[1.25vw] h-[1.25vw] bg-[url(./assets/chevron-left.png)] transition-all" :style="{ backgroundSize: '100% 100%', opacity: inventory.craftingInProgress || inventory.craftAmount <= 1 ? 0.3 : 1, cursor: inventory.craftingInProgress || inventory.craftAmount <= 1 ? 'default' : 'pointer', pointerEvents: inventory.craftingInProgress || inventory.craftAmount <= 1 ? 'none' : 'auto' }"></div>
                          <p class="text-[#CAA580]">{{ inventory.craftAmount }}</p>
                          <div @click="!inventory.craftingInProgress ? inventory.craftAmount++ : null" class="w-[1.25vw] h-[1.25vw] bg-[url(./assets/chevron-right.png)] transition-all" :style="{ backgroundSize: '100% 100%', opacity: inventory.craftingInProgress ? 0.3 : 1, cursor: inventory.craftingInProgress ? 'default' : 'pointer', pointerEvents: inventory.craftingInProgress ? 'none' : 'auto' }"></div>
                        </div>
                      </div>
                      <!-- Ingredients + craft button -->
                      <div class="w-[68%] h-full flex flex-col justify-between">
                        <div class="gap-1">
                          <p class="text-[#CAA580] text-lg">Ingredients</p>
                          <p class="text-[#898888] text-xs">{{ inventory.craftRecipe.requiredItems.map(function(r) { return r.label }).join(', ') }}</p>
                        </div>
                        <div class="w-full h-[4vw] flex gap-1 overflow-x-auto overflow-y-hidden flex-nowrap">
                          <div v-for="req in inventory.craftRecipe.requiredItems" :key="req.name" class="w-[4vw] shrink-0 h-full rounded p-1 relative" style="background-color: rgba(255,138,5,0.06);">
                            <span class="absolute top-0.5 right-1 text-[10px] text-white/40">{{ req.requiredAmount * inventory.craftAmount }}x</span>
                            <span class="absolute top-0.5 left-1 text-[10px] text-white/40">{{ ((req.weight || 0) * req.requiredAmount * inventory.craftAmount).toFixed(2) }}kg</span>
                            <img :src="getItemImage(req.name)" @error="onImgError" class="absolute inset-0 m-auto w-[40%] h-[60%] object-contain">
                            <p class="absolute bottom-0.5 left-0 right-0 text-center text-[10px] text-white/70 truncate px-0.5">{{ req.label }}</p>
                          </div>
                        </div>
                        <div class="w-full h-[2vw] flex justify-between items-center">
                          <div>
                            <p class="text-[#CAA580] text-sm">Process Time</p>
                            <p class="text-[#898888] text-[0.55vw]">{{ (inventory.craftRecipe.timerForPerAmount / 1000).toFixed(0) }} seconds per one!</p>
                          </div>
                          <div @click="inventory.canCraft ? postNUI('StartCraft', { rewardName: inventory.craftRecipe.rewardName, amount: inventory.craftAmount }) : null" class="h-full px-2 flex justify-center text-xs font-semibold items-center bg-[url(./assets/craft-button-background.png)] cursor-pointer transition-all hover:opacity-70" :style="{ backgroundSize: '100% 100%', opacity: inventory.canCraft && !inventory.craftingInProgress ? 1 : 0.4, pointerEvents: inventory.canCraft && !inventory.craftingInProgress ? 'auto' : 'none' }">
                            {{ inventory.craftingInProgress ? 'Crafting...' : 'Start Crafting!' }}
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
              </div>


              <!-- Second Inventory: clothing -->
              <div v-else-if="inventory.secondInventoryType === 'clothing'" key="clothing" class="w-full h-full flex flex-col justify-between items-center">
                  <div height="9%" class="p-2 flex justify-between items-center h-[9%] w-full bg-[url(./assets/header-background.png)]" style="background-size: 100% 100%;">
                    <p class="text-xl">Clothing Menu</p>
                    <div class="w-[2vw] h-[2vw]  flex justify-center items-center rounded-md bg-black/10">
                        <img src="./assets/clothing-icon-big.png">
                    </div>
                  </div>
                  <div class="w-full h-[77%] relative">
                      <img src="./assets/character-image.png" class="absolute inset-0 m-auto h-full object-contain">
                      <template v-for="slot in clothingSlots" :key="slot.id">
                        <div
                          class="absolute flex items-center gap-2"
                          :style="{
                            left: slot.x + '%',
                            top: slot.y + '%',
                            transform: `translate(-50%, -50%) rotate(${slot.rotate}deg)`,
                          }"
                        >
                          <img v-if="slot.lineSide === 'left'" src="./assets/clothing-line.png" class="pointer-events-none" style="height: 4px;">
                          <div
                            @click="onClothingClick(slot)"
                            class="w-[2.5vw] h-[2.5vw] shrink-0 bg-[url(./assets/clothing-menu-background.png)] flex justify-center items-center transition-all hover:opacity-70 cursor-pointer"
                            style="background-size: 100% 100%;"
                            :title="slot.label"
                          >
                            <img :src="getAsset(slot.icon)" >
                          </div>
                          <img v-if="slot.lineSide === 'right'" src="./assets/clothing-line.png" class="pointer-events-none" style="height: 4px;">
                        </div>
                      </template>
                  </div>
                  <div @click="inventory.secondInventoryType = inventory.secondInventoryType === 'clothing' ? (inventory.invType === 'main' ? 'drop' : 'inventory') : 'clothing'" class="w-full h-[5vh] flex justify-center items-center bg-[url(./assets/close-clothing-menu-background.png)] cursor-pointer transition-all hover:opacity-70" style="background-size: 100% 100%;">
                      CLOSE CLOTHING MENU
                  </div>
              </div>

              <!-- Drop Inventory -->
              <div v-else-if="inventory.secondInventoryType === 'drop'" key="drop" class="w-full h-full flex flex-col justify-between items-center">
                  <div class="p-2 flex justify-between items-center h-[9%] w-full bg-[url(./assets/header-background.png)]" style="background-size: 100% 100%;">
                    <p class="text-xl">Ground{{ inventory.nearbyDropId ? ' - ' + inventory.nearbyDropId : '' }}</p>
                    <div class="w-[2vw] h-[2vw] flex justify-center items-center rounded-md bg-black/10">
                        <img src="./assets/inventory-icon.png">
                    </div>
                  </div>
                  <div class="w-full h-[6vh] flex flex-col items-center justify-center gap-1">
                    <div class="weight-bar">
                      <div class="weight-bar-fill" :style="{ width: (inventory.LuaConfig.DropInventory ? (inventory.dropCurrentWeight / inventory.LuaConfig.DropInventory.MaxWeight * 100) : 0) + '%' }"></div>
                    </div>
                    <div class="w-full flex justify-between items-center">
                        <p class="text-sm text-[#BEB592]">Max Weight</p>
                        <p class="text-sm text-[#BEB592]"><span class="font-semibold">{{ inventory.dropCurrentWeight }}</span>/{{ inventory.LuaConfig.DropInventory ? inventory.LuaConfig.DropInventory.MaxWeight : 100 }}{{ inventory.LuaConfig.WeightMeasure || 'kg' }}</p>
                    </div>
                  </div>
                  <div class="w-full h-[80%] grid grid-cols-5 gap-1.5 content-start overflow-y-auto">
                      <div v-for="i in (inventory.LuaConfig.DropInventory ? inventory.LuaConfig.DropInventory.Slots : 25)" :key="i" @mousedown="onDropZoneMouseDown($event, i)" @mouseup="onDropSlotMouseUp(i)" class="aspect-square bg-white/[0.08] rounded transition-all hover:opacity-70 p-1 relative flex flex-col items-center justify-center" :class="{ 'opacity-30': dragFrom === i && dragSource === 'dropzone' }">
                          <template v-if="inventory.getDropZoneItemAtSlot(i)">
                              <span class="absolute top-0.5 right-1 text-[10px] text-white/40">{{ inventory.getDropZoneItemAtSlot(i).amount || 1 }}x</span>
                              <span class="absolute top-0.5 left-1 text-[10px] text-white/40">{{ ((inventory.getDropZoneItemAtSlot(i).weight || 0) * (inventory.getDropZoneItemAtSlot(i).amount || 1)).toFixed(2) }}kg</span>
                              <img :src="getItemImage(inventory.getDropZoneItemAtSlot(i).name)" @error="onImgError" class="absolute inset-0 m-auto max-w-[40%] max-h-[60%] object-contain">
                              <svg v-if="inventory.getDropZoneItemAtSlot(i).type === 'item_weapon' && inventory.getDropZoneItemAtSlot(i).durability != null" class="absolute left-1 top-1/2 -translate-y-1/2" width="12" height="12" viewBox="0 0 36 36">
                                <circle cx="18" cy="18" r="15" fill="none" stroke="rgba(0,0,0,0.3)" stroke-width="4"></circle>
                                <circle cx="18" cy="18" r="15" fill="none" :stroke="getDegradationColor(inventory.getDropZoneItemAtSlot(i).durability)" stroke-width="4" stroke-linecap="round" :stroke-dasharray="(inventory.getDropZoneItemAtSlot(i).durability / 100 * 94.2) + ' 94.2'" transform="rotate(-90 18 18)"></circle>
                              </svg>
                              <p class="absolute bottom-0.5 left-0 right-0 text-center text-[10px] text-white/70 truncate px-0.5">{{ inventory.getDropZoneItemAtSlot(i).label }}</p>
                          </template>
                          <template v-else>
                              <span class="absolute top-0.5 right-1 text-[10px] text-white/40">{{ i }}</span>
                          </template>
                      </div>
                  </div>
              </div>

              </Transition>
          </div>

          <!-- Context Menu: Gun Belt (Ammo) -->
          <Transition name="fade">
            <div v-if="contextMenu.show && contextMenu.item && contextMenu.item.type === 'item_ammo'" class="fixed z-50 w-[17vw] gap-1 p-3 px-5 bg-[url(./assets/context-background.png)] flex flex-col items-center rounded" :style="{ left: contextMenu.x + 'px', top: contextMenu.y + 'px' }" @click.stop style="background-size: 100% 100%;">
                <div class="w-full flex justify-between items-center">
                    <p>{{ contextMenu.item.label }}</p>
                    <div class="w-[1.75vw] h-[1.75vw] rounded-md bg-black/10 flex justify-center items-center">
                      <img src="./assets/hand-icon.png">
                    </div>
                </div>
                <div class="w-full h-px bg-black/20"></div>
                <p class="text-xs text-[#4E4D4D] w-full">{{ contextMenu.item.desc }}</p>
                <div class="w-full h-px bg-black/20"></div>
                <div class="w-full flex flex-col gap-1 max-h-[30vh] overflow-y-auto">
                  <template v-if="getAmmoList().length > 0">
                    <div v-for="a in getAmmoList()" :key="a.key" @click="onAmmoClick(a.key, a.label)" class="w-full flex justify-between items-center p-2 cursor-pointer transition-all hover:opacity-70 bg-[url(./assets/settings-item-background.png)]" style="background-size: 100% 100%;">
                      <p class="text-xs text-black">{{ a.label }}</p>
                      <p class="text-xs text-black">{{ a.count }}</p>
                    </div>
                  </template>
                  <div v-else class="w-full flex justify-center items-center p-2 bg-[url(./assets/settings-item-background.png)]" style="background-size: 100% 100%;">
                    <p class="text-xs text-[#565353]">Empty</p>
                  </div>
                </div>
            </div>
          </Transition>

          <!-- Context Menu: Normal Items -->
          <Transition name="fade">
            <div v-if="contextMenu.show && contextMenu.item && contextMenu.item.type !== 'item_ammo'" class="fixed z-50 w-[17vw] gap-1 p-3 px-5 bg-[url(./assets/context-background.png)] flex flex-col items-center rounded" :style="{ left: contextMenu.x + 'px', top: contextMenu.y + 'px' }" @click.stop style="background-size: 100% 100%;">
                <!-- Header -->
                <div class="w-full flex justify-between items-center">
                    <p>{{ contextMenu.item.metadata?.label || contextMenu.item.custom_label || contextMenu.item.label }}</p>
                    <div class="w-[1.75vw] h-[1.75vw] rounded-md bg-black/10 flex justify-center items-center">
                      <img src="./assets/hand-icon.png">
                    </div>
                </div>
                <div class="w-full h-px bg-black/20"></div>
                <!-- Basic Info -->
                <div class="w-full flex flex-col gap-1">
                  <div class="w-full flex justify-between items-center">
                      <div class="gap-1 flex">
                        <img src="./assets/name-icon.png">
                        <p class="text-[#4E4D4D]">Item Label</p>
                      </div>
                      <p>{{ contextMenu.item.metadata?.label || contextMenu.item.custom_label || contextMenu.item.label }}</p>
                  </div>
                  <div class="w-full flex justify-between items-center">
                      <div class="gap-1 flex items-center">
                        <img src="./assets/weight-icon.png">
                        <p class="text-[#4E4D4D]">Item Weight</p>
                      </div>
                      <p>{{ (contextMenu.item.metadata?.weight || contextMenu.item.weight || 0) }}{{ inventory.LuaConfig.WeightMeasure || 'kg' }}</p>
                  </div>
                </div>
                <!-- Item Info (metadata / weapon fields) -->
                <div v-if="hasItemInfo(contextMenu.item)" class="w-full flex flex-col mt-4 gap-1">
                    <p>Item Info</p>
                    <div class="w-full h-px bg-black/20"></div>
                    <div v-if="contextMenu.item.serial_number" class="w-full flex justify-between items-center">
                      <p>Serial Number</p>
                      <p class="text-[#565353]">{{ contextMenu.item.serial_number }}</p>
                    </div>
                    <div v-if="contextMenu.item.maxDegradation > 0" class="w-full flex justify-between items-center">
                      <p>Durability</p>
                      <p :style="{ color: getDegradationColor(getDegradation(contextMenu.item)) }">{{ getDegradation(contextMenu.item).toFixed(0) }}%</p>
                    </div>
                    <div v-if="contextMenu.item.type === 'item_weapon' && contextMenu.item.durability != null" class="w-full flex justify-between items-center">
                      <p>Durability</p>
                      <p :style="{ color: getDegradationColor(contextMenu.item.durability) }">{{ contextMenu.item.durability.toFixed(1) }}%</p>
                    </div>
                    <template v-if="contextMenu.item.metadata">
                      <template v-for="(value, key) in contextMenu.item.metadata" :key="key">
                        <div v-if="!isReservedMeta(key)" class="w-full flex justify-between items-center">
                          <p>{{ key }}</p>
                          <p class="text-[#565353]">{{ value }}</p>
                        </div>
                      </template>
                    </template>
                </div>
                <!-- Description -->
                <div v-if="getItemDesc(contextMenu.item)" class="mt-4 w-full flex flex-col gap-1">
                  <div class="w-full flex justify-between items-center">
                      <p>Description</p>
                      <div class="w-[1.75vw] h-[1.75vw] rounded-md bg-black/10 flex justify-center items-center">
                        <img src="./assets/description-icon.png">
                      </div>
                  </div>
                  <div class="w-full h-px bg-black/20"></div>
                  <p class="text-xs text-[#565353]">{{ getItemDesc(contextMenu.item) }}</p>
                </div>
                <!-- Weapon Components -->
                <div v-if="getWeaponComponents(contextMenu.item).length > 0" class="mt-4 w-full flex flex-col gap-1">
                  <p>Components</p>
                  <div class="w-full h-px bg-black/20"></div>
                  <div v-for="(c, ci) in getWeaponComponents(contextMenu.item)" :key="ci" class="w-full flex justify-between items-center">
                    <p class="text-xs text-[#4E4D4D]">{{ c.type || c.comp }}</p>
                    <p class="text-xs text-[#565353]">{{ c.label }}</p>
                  </div>
                </div>
            </div>
          </Transition>

          <!-- Ammo Amount Prompt -->
          <Transition name="fade">
            <div v-if="ammoPrompt.show" class="fixed inset-0 z-50 flex items-center justify-center" @click.self="ammoPrompt.show = false">
              <div class="w-[17vw] bg-[url(./assets/context-background.png)] p-3 px-5 rounded flex flex-col gap-2 items-center" style="background-size: 100% 100%;" @click.stop>
                <div class="w-full flex justify-between items-center">
                  <p>{{ ammoPrompt.ammoLabel }}</p>
                  <div class="w-[1.75vw] h-[1.75vw] rounded-md bg-black/10 flex justify-center items-center">
                    <img src="./assets/hand-icon.png">
                  </div>
                </div>
                <div class="w-full h-px bg-black/20"></div>
                <div class="w-full flex flex-col gap-2 mt-1">
                  <div class="w-full h-[2.5vw] bg-[url(./assets/amount-background.png)] flex justify-center items-center" style="background-size: 100% 100%;">
                    <input type="number" v-model.number="ammoPrompt.amount" min="1" class="w-full h-full text-center text-xl text-[#BEB592]" placeholder="1" @keyup.enter="onAmmoPromptConfirm">
                  </div>
                  <div class="w-full flex gap-2">
                    <div @click="ammoPrompt.show = false" class="flex-1 h-[2.2vw] flex justify-center items-center cursor-pointer transition-all hover:opacity-70 bg-[url(./assets/buttons-background.png)]" style="background-size: 100% 100%;">
                      <p class="text-sm text-[#BEB592]">Cancel</p>
                    </div>
                    <div @click="onAmmoPromptConfirm" class="flex-1 h-[2.2vw] flex justify-center items-center cursor-pointer transition-all hover:opacity-70 bg-[url(./assets/buttons-background.png)]" style="background-size: 100% 100%;">
                      <p class="text-sm text-[#BEB592]">Confirm</p>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </Transition>

          <!-- Player Select Modal -->
          <Transition name="fade">
            <div v-if="inventory.showPlayerSelect" class="fixed inset-0 z-50 flex items-center justify-center" @click.self="onPlayerSelectClose">
              <div class="w-[17vw] bg-[url(./assets/context-background.png)] p-3 px-5 rounded flex flex-col gap-2 items-center" style="background-size: 100% 100%;" @click.stop>
                <div class="w-full flex justify-between items-center">
                  <p>Select Player</p>
                  <div class="w-[1.75vw] h-[1.75vw] rounded-md bg-black/10 flex justify-center items-center">
                    <img src="./assets/user-icon.png">
                  </div>
                </div>
                <div class="w-full h-px bg-black/20"></div>
                <div class="w-full flex flex-col gap-1 max-h-[30vh] overflow-y-auto">
                  <div v-for="p in inventory.nearPlayersList" :key="p.player" @click="onPlayerSelect(p.player)" class="w-full flex justify-between items-center p-2 cursor-pointer transition-all hover:opacity-70 bg-[url(./assets/settings-item-background.png)]" style="background-size: 100% 100%;">
                    <div class="flex items-center gap-2">
                      <div class="w-[1.75vw] h-[1.75vw] rounded-md bg-black/10 flex justify-center items-center">
                        <img src="./assets/user-icon.png">
                      </div>
                      <p>{{ p.label }}</p>
                    </div>
                    <p class="text-xs text-[#4E4D4D]">ID: {{ p.player }}</p>
                  </div>
                </div>
                <div @click="onPlayerSelectClose" class="w-full h-[2.2vw] flex justify-center items-center cursor-pointer transition-all hover:opacity-70 bg-[url(./assets/buttons-background.png)] mt-1" style="background-size: 100% 100%;">
                  <p class="text-sm text-[#BEB592]">Cancel</p>
                </div>
              </div>
            </div>
          </Transition>
      </div>
      </Transition>

      <Transition name="fade">
      <div v-if="inventory.showHotbar" class="w-full flex justify-center items-center h-[14%] mt-auto" >
          <div class="w-[32%] h-full bg-[url(./assets/hotbar-background.png)] flex justify-center items-center" style="background-size: 100% 100%;">
            <div class="grid grid-cols-5 gap-1.5 p-3 h-full w-full place-items-center">
              <div v-for="i in 5" :key="i" class="aspect-square h-[calc(100%-4px)] bg-white/[0.08] rounded transition-all hover:opacity-70 p-1 relative flex flex-col items-center justify-center">
                  <template v-if="inventory.getItemAtSlot(i)">
                      <span class="absolute top-0.5 right-1 text-[10px] text-white/40">{{ slotCount(inventory.getItemAtSlot(i)) }}</span>
                      <span class="absolute top-0.5 left-1 text-[10px] text-white/40">{{ slotWeight(inventory.getItemAtSlot(i)) }}kg</span>
                      <img :src="getItemImage(inventory.getItemAtSlot(i).name)" @error="onImgError" class="absolute inset-0 m-auto max-w-[40%] max-h-[60%] object-contain">
                      <svg v-if="inventory.getItemAtSlot(i).type === 'item_weapon' && inventory.getItemAtSlot(i).durability != null" class="absolute left-1 top-1/2 -translate-y-1/2" width="10" height="10" viewBox="0 0 36 36">
                        <circle cx="18" cy="18" r="15" fill="none" stroke="rgba(0,0,0,0.3)" stroke-width="4"></circle>
                        <circle cx="18" cy="18" r="15" fill="none" :stroke="getDegradationColor(inventory.getItemAtSlot(i).durability)" stroke-width="4" stroke-linecap="round" :stroke-dasharray="(inventory.getItemAtSlot(i).durability / 100 * 94.2) + ' 94.2'" transform="rotate(-90 18 18)"></circle>
                      </svg>
                      <span v-if="isEquippedWeapon(inventory.getItemAtSlot(i))" class="absolute left-1 text-[10px] font-semibold leading-none text-[#2fd06c] pointer-events-none" style="top: calc(50% - 19px); text-shadow: 0 1px 2px rgba(0,0,0,0.65);">E</span>
                      <p class="absolute bottom-0.5 left-0 right-0 text-center text-[10px] text-white/70 truncate px-0.5">{{ inventory.getItemAtSlot(i).label }}</p>
                  </template>
                  <template v-else>
                      <span class="absolute top-0.5 right-1 text-[10px] text-white/40">{{ i }}</span>
                  </template>
              </div>
            </div>
          </div>
      </div>
      </Transition>

      <div class="fixed bottom-20 left-0 right-0 flex justify-center gap-1.5 items-end pointer-events-none z-[5]">
          <TransitionGroup name="notif">
            <div
              v-for="n in inventory.itemNotifications"
              :key="n.id"
              class="w-[5vw] h-[5vw] rounded p-1 relative flex flex-col items-center justify-center"
              :style="{ backgroundColor: n.type === 'remove' ? 'rgba(147, 91, 91, 0.38)' : n.type === 'used' ? 'rgba(100, 149, 237, 0.38)' : 'rgba(156, 178, 83, 0.38)' }"
            >
              <span class="absolute top-0.5 right-1 text-[8px] text-white/40">{{ n.count }}x</span>
              <span class="absolute top-0.5 left-0.5 text-[7px] text-white/40">{{ n.type === 'remove' ? 'Removed' : n.type === 'used' ? 'Used' : 'Added' }}</span>
              <img :src="getItemImage(n.name)" @error="onImgError" class="absolute inset-0 m-auto w-[40%] h-[60%] object-contain">
              <p class="absolute bottom-0.5 left-0 right-0 text-center text-[7px] text-white/70 truncate px-0.5">{{ n.label }}</p>
            </div>
          </TransitionGroup>
      </div>


  </div>
</template>
