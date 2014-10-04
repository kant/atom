_ = require 'underscore-plus'
spacePen = require 'space-pen'
{Subscriber} = require 'emissary'

Subscriber.includeInto(spacePen.View)

jQuery = spacePen.jQuery
originalCleanData = jQuery.cleanData
jQuery.cleanData = (elements) ->
  jQuery(element).view()?.unsubscribe() for element in elements
  originalCleanData(elements)

NativeEventNames = new Set
NativeEventNames.add(nativeEvent) for nativeEvent in ["blur", "focus", "focusin",
"focusout", "load", "resize", "scroll", "unload", "click", "dblclick", "mousedown",
"mouseup", "mousemove", "mouseover", "mouseout", "mouseenter", "mouseleave", "change",
"select", "submit", "keydown", "keypress", "keyup", "error", "contextmenu"]

originalTrigger = jQuery.fn.trigger
jQuery.fn.trigger = (eventName, data) ->
  if NativeEventNames.has(eventName)
    originalTrigger.call(this, eventName, data)
  else
    for element in this
      atom.commands.dispatch(element, eventName, data)
    this

HandlersByOriginalHandler = new WeakMap

JQueryEventAdd = jQuery.event.add
jQuery.event.add = (elem, types, originalHandler, data, selector) ->
  handler = (event) ->
    if arguments.length is 1 and event.originalEvent?.detail?
      {detail} = event.originalEvent
      if Array.isArray(detail)
        console.log "calling handler", [event].concat(detail)
        originalHandler.apply(this, [event].concat(detail))
      else
        console.log "calling handler", detail
        originalHandler.call(this, event, detail)
    else
      console.log "failling through"
      originalHandler.apply(this, arguments)

  HandlersByOriginalHandler.set(originalHandler, handler)
  JQueryEventAdd.call(this, elem, types, handler, data, selector)

JQueryEventRemove = jQuery.event.remove
jQuery.event.remove = (elem, types, originalHandler, selector, mappedTypes) ->
  if originalHandler?
    handler = HandlersByOriginalHandler.get(originalHandler) ? originalHandler
  JQueryEventRemove(elem, types, handler, selector, mappedTypes)

tooltipDefaults =
  delay:
    show: 1000
    hide: 100
  container: 'body'
  html: true
  placement: 'auto top'
  viewportPadding: 2

humanizeKeystrokes = (keystroke) ->
  keystrokes = keystroke.split(' ')
  keystrokes = (_.humanizeKeystroke(stroke) for stroke in keystrokes)
  keystrokes.join(' ')

getKeystroke = (bindings) ->
  if bindings?.length
    "<span class=\"keystroke\">#{humanizeKeystrokes(bindings[0].keystrokes)}</span>"
  else
    ''

requireBootstrapTooltip = _.once ->
  atom.requireWithGlobals('bootstrap/js/tooltip', {jQuery})

# options from http://getbootstrap.com/javascript/#tooltips
jQuery.fn.setTooltip = (tooltipOptions, {command, commandElement}={}) ->
  requireBootstrapTooltip()

  tooltipOptions = {title: tooltipOptions} if _.isString(tooltipOptions)

  if commandElement
    bindings = atom.keymaps.findKeyBindings(command: command, target: commandElement[0])
  else if command
    bindings = atom.keymaps.findKeyBindings(command: command)

  tooltipOptions.title = "#{tooltipOptions.title} #{getKeystroke(bindings)}"

  @tooltip(jQuery.extend({}, tooltipDefaults, tooltipOptions))

jQuery.fn.hideTooltip = ->
  tip = @data('bs.tooltip')
  if tip
    tip.leave(currentTarget: this)
    tip.hide()

jQuery.fn.destroyTooltip = ->
  @hideTooltip()
  requireBootstrapTooltip()
  @tooltip('destroy')

# Hide tooltips when window is resized
jQuery(document.body).on 'show.bs.tooltip', ({target}) ->
  windowHandler = -> jQuery(target).hideTooltip()
  jQuery(window).one('resize', windowHandler)
  jQuery(target).one 'hide.bs.tooltip', ->
    jQuery(window).off('resize', windowHandler)

jQuery.fn.setTooltip.getKeystroke = getKeystroke
jQuery.fn.setTooltip.humanizeKeystrokes = humanizeKeystrokes

Object.defineProperty jQuery.fn, 'element', get: -> @[0]

module.exports = spacePen
