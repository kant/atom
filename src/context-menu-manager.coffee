{$} = require './space-pen-extensions'
_ = require 'underscore-plus'
remote = require 'remote'
path = require 'path'
CSON = require 'season'
fs = require 'fs-plus'
{specificity} = require 'clear-cut'
{Disposable} = require 'event-kit'
Grim = require 'grim'
MenuHelpers = require './menu-helpers'

SpecificityCache = {}

# Extended: Provides a registry for commands that you'd like to appear in the
# context menu.
#
# An instance of this class is always available as the `atom.contextMenu`
# global.
module.exports =
class ContextMenuManager
  constructor: ({@resourcePath, @devMode}) ->
    @definitions = {'.overlayer': []} # TODO: Remove once color picker package stops touching private data
    @clear()

    atom.keymaps.onDidLoadBundledKeymaps => @loadPlatformItems()

  loadPlatformItems: ->
    menusDirPath = path.join(@resourcePath, 'menus')
    platformMenuPath = fs.resolve(menusDirPath, process.platform, ['cson', 'json'])
    map = CSON.readFileSync(platformMenuPath)
    atom.contextMenu.add(map['context-menu'])

  # Public: Add context menu items scoped by CSS selectors.
  #
  # ## Examples
  #
  # To add a context menu, pass a selector matching the elements to which you
  # want the menu to apply as the top level key, followed by a menu descriptor.
  # The invocation below adds a global 'Help' context menu item and a 'History'
  # submenu on the editor supporting undo/redo. This is just for example
  # purposes and not the way the menu is actually configured in Atom by default.
  #
  # ```coffee
  # atom.contextMenu.add {
  #   '.workspace': [{label: 'Help', command: 'application:open-documentation'}]
  #   '.editor':    [{
  #     label: 'History',
  #     submenu: [
  #       {label: 'Undo': command:'core:undo'}
  #       {label: 'Redo': command:'core:redo'}
  #     ]
  #   }]
  # }
  # ```
  #
  # ## Arguments
  #
  # * `itemsBySelector` An {Object} whose keys are CSS selectors and whose
  #   values are {Array}s of item {Object}s containing the following keys:
  #   * `label` (Optional) A {String} containing the menu item's label.
  #   * `command` (Optional) A {String} containing the command to invoke on the
  #     target of the right click that invoked the context menu.
  #   * `submenu` (Optional) An {Array} of additional items.
  #   * `type` (Optional) If you want to create a separator, provide an item
  #      with `type: 'separator'` and no other keys.
  #   * `created` (Optional) A {Function} that is called on the item each time a
  #     context menu is created via a right click. You can assign properties to
  #    `this` to dynamically compute the command, label, etc. This method is
  #    actually called on a clone of the original item template to prevent state
  #    from leaking across context menu deployments. Called with the following
  #    argument:
  #     * `event` The click event that deployed the context menu.
  #   * `shouldDisplay` (Optional) A {Function} that is called to determine
  #     whether to display this item on a given context menu deployment. Called
  #     with the following argument:
  #     * `event` The click event that deployed the context menu.
  add: (itemsBySelector) ->
    # Detect deprecated file path as first argument
    unless typeof itemsBySelector is 'object'
      Grim.deprecate("ContextMenuManage::add has changed to take a single object as its argument. Please consult the documentation.")
      itemsBySelector = arguments[1]
      devMode = arguments[2]?.devMode

    # Detect deprecated format for items object
    for key, value of itemsBySelector
      unless _.isArray(value)
        Grim.deprecate("The format for declaring context menu items has changed. Please consult the documentation.")
        itemsBySelector = @convertLegacyItemsBySelector(itemsBySelector, devMode)

    addedItemSets = []

    for selector, items of itemsBySelector
      itemSet = new ContextMenuItemSet(selector, items)
      addedItemSets.push(itemSet)
      @itemSets.push(itemSet)

    new Disposable =>
      for itemSet in addedItemSets
        @itemSets.splice(@itemSets.indexOf(itemSet), 1)

  templateForElement: (target) ->
    @templateForEvent({target})

  templateForEvent: (event) ->
    template = []
    currentTarget = event.target

    while currentTarget?
      currentTargetItems = []
      matchingItemSets =
        @itemSets.filter (itemSet) -> currentTarget.webkitMatchesSelector(itemSet.selector)

      for itemSet in matchingItemSets
        for item in itemSet.items
          continue if item.devMode and not @devMode
          item = Object.create(item)
          if typeof item.shouldDisplay is 'function'
            continue unless item.shouldDisplay(event)
          item.created?(event)
          MenuHelpers.merge(currentTargetItems, MenuHelpers.cloneMenuItem(item), itemSet.specificity)

      for item in currentTargetItems
        MenuHelpers.merge(template, item, false)

      currentTarget = currentTarget.parentElement

    template

  convertLegacyItemsBySelector: (legacyItemsBySelector, devMode) ->
    itemsBySelector = {}

    for selector, commandsByLabel of legacyItemsBySelector
      itemsBySelector[selector] = @convertLegacyItems(commandsByLabel, devMode)

    itemsBySelector

  convertLegacyItems: (legacyItems, devMode) ->
    items = []

    for label, commandOrSubmenu of legacyItems
      if typeof commandOrSubmenu is 'object'
        items.push({label, submenu: @convertLegacyItems(commandOrSubmenu, devMode), devMode})
      else if commandOrSubmenu is '-'
        items.push({type: 'separator'})
      else
        items.push({label, command: commandOrSubmenu, devMode})

    items

  # Public: Request a context menu to be displayed.
  #
  # * `event` A DOM event.
  showForEvent: (event) ->
    @activeElement = event.target
    menuTemplate = @templateForEvent(event)

    return unless menuTemplate?.length > 0
    remote.getCurrentWindow().emit('context-menu', menuTemplate)
    return

  clear: ->
    @activeElement = null
    @itemSets = []
    @add '.workspace': [{
      label: 'Inspect Element'
      command: 'application:inspect'
      devMode: true
      created: (event) ->
        {pageX, pageY} = event
        @commandDetail = {x: pageX, y: pageY}
    }]

class ContextMenuItemSet
  constructor: (@selector, @items) ->
    @specificity = (SpecificityCache[@selector] ?= specificity(@selector))
