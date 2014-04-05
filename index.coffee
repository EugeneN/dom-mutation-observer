# TODO make this a polymorphic interface

root = window 

$ = require 'jquery'
{pubsubhub} = require 'libprotein'
{dispatch_impl} = require 'libprotocol'
{info, warn, error, debug, nullog} = dispatch_impl 'ILogger', 'MutationObserver'

ie_version = ->
    myNav = root.navigator.userAgent.toLowerCase()
    if "msie" in myNav then (parseInt(myNav.split('msie')[1])) else false;

# http://stackoverflow.com/questions/10868104/can-you-have-a-javascript-hook-trigger-after-a-dom-elements-style-object-change
MutationObserver = root.MutationObserver or root.WebKitMutationObserver or root.MozMutationObserver

isDOMAttrModifiedSupported = do ->
    p = root.document.createElement 'p'
    flag = false

    if p.addEventListener
        p.addEventListener(
            'DOMAttrModified'
            -> flag = true
            false
        )

    else if p.attachEvent
        p.attachEvent(
            'onDOMAttrModified'
            -> flag = true
        )

    else
        return false

    p.setAttribute 'id', 'target'

    flag

observe = (node, opts, handler) ->
    if MutationObserver
        observer = new MutationObserver (mutations) ->
            mutations.map (e) ->
                handler e.target, e.attributeName

        observer.observe node, { attributes: true, subtree: opts.subtree }

    else if isDOMAttrModifiedSupported
        ($ node).bind 'DOMAttrModified', (e) ->
            handler this, e.attrName

    else if 'onpropertychange' in root.document.body
         ($ node).bind 'propertychange', (e) ->
            handler this, root.event.propertyName

    else
        throw "DOM Mutation Observer not available"


walkDOM = (node, f) ->
        f node
        node = node.firstChild

        while node
            walkDOM node, f
            node = node.nextSibling

observe_dom_added = (root_node, cont) ->
    # observes root_node for creation of new elements
    # calls cont with newly created elements
    # can't handle changes made by assigning to .innerHTML !
    is_ie = ie_version()

    if is_ie and is_ie < 9
        {pub, sub} = pubsubhub()

        get_wrapper = (orig_fn_name) ->
            (args...) ->
                ret = this[orig_fn_name].apply(this, args)
                debug "Patched call: #{orig_fn_name} with args:", args...
                setTimeout(
                    -> pub 'node_changed', args...
                    0
                )
                ret

        patch = (o, fn_name) ->
            orig_fn_name = '_' + fn_name
            o.prototype[orig_fn_name] = o.prototype[fn_name]
            o.prototype[fn_name] = get_wrapper (orig_fn_name)
            
        try
            ['appendChild', 'insertChild', 'replaceChild', 'cloneNode', 'insertBefore'].map (fn_name) -> 
                patch Element, fn_name
        catch e
            error "Can't init dom observer, don't use IE7"

        sub 'node_changed', ([node]...) -> cont node

    else
        dom_parser = dispatch_impl 'IDom', root_node
        # TODO use MutationObserver instead when applicable
        dom_parser.add_event_listener "DOMNodeInserted", (event) ->
            console.log "DOMNodeInserted", event.target, event.target.id
            dom_fragment_root = event.target

            if dom_fragment_root._meta_mut_observer is true
                # debug "skipping sub-node", dom_fragment_root
            else
                # ie reports every node in an inserted sub-tree as a new event
                # other browsers report only top-level nodes
                # hence ie gets dna cells reinstantiated (sub-tree depth) times
                walkDOM dom_fragment_root, (n) -> n._meta_mut_observer = true
                cont dom_fragment_root


module.exports = {observe, observe_dom_added}
