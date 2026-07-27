/* global apex,$ */
window.FOS = window.FOS || {};
FOS.utils = window.FOS.utils || {};

/**
 *
 * @param {object}      daContext                       Dynamic Action context as passed in by APEX
 * @param {object}   	config 	                    	Configuration object containing the plugin settings
 * @param {string}   	config.action                   The action to execute [show-spinner|remove-spinner|convert-default]
 * @param {string}   	config.spinnerType              Style of the spinner [default|fos-sa-spinner-style-one|...]
 * @param {string}   	config.spinnerColor             Color of the spinner element
 * @param {string}   	config.spinnerHTML              HTML part of the custom spinner
 * @param {string}   	config.spinnerCSS               CSS part of the custom spinner
 * @param {string}   	config.overlayType              The type of the overlay [none|on-element|on-page]
 * @param {string}   	config.overlayColor             Color of the overlay element
 * @param {number}   	config.overlayOpacity           Sets the opacity level for the element [0-100]
 * @param {string}   	[config.accessText]             Text used by Assistive Technologies
 * @param {string}   	[config.spinnerClass]           Custom class on the spinner element               
 */

FOS.utils.spinnerActions = (function ($) {

    const OVERLAY_BODY_STYLE = 'fos-sa-overlay-body';
    const OVERLAY_REGION_STYLE = 'fos-sa-overlay-region';
    const REGION_HAS_OVERLAY = 'fos-sa-region-has-overlay';
    const REGION_HAS_SPINNER = 'fos-sa-region-has-spinner';
    const SPINNER_WITH_OVERLAY = 'fos-sa-spinner-has-overlay';
    const NATIVE_SPINNER_SELECTOR = '.u-Processing[role=alert]';
    const CUSTOM_SPINNER_CLASS = 'fos-spinner-actions-custom';
    const CUSTOM_SPINNER_SELECTOR = '.fos-spinner-actions-custom[role=alert]';

    let addCustomSpinner = function (id, spinnerHTML, spinnerCSS, spinner) {
        let newSpinner = $(spinnerHTML);
        newSpinner[0].classList.add(CUSTOM_SPINNER_CLASS);
        newSpinner.attr('role', 'alert');
        if (spinner) {
            newSpinner.attr('style', spinner.attr('style'));
        }
        newSpinner.css({ 'position': 'absolute', 'z-index': 999 });
        let toAppend = '<style id="fos-spinner-actions-css-"' + id + '>' + spinnerCSS + '</style>';
        $('head').append(toAppend);
        return newSpinner;
    };

    let showSpinner = function (daContext, config) {
        apex.debug.info('daContext', daContext);
        apex.debug.info('config', config);

        let spinner, id, affectedElement;
        let me = this;

        // if no affectedElement provided, set it to body
        if (!daContext.action.affectedElementsType) {
            daContext.affectedElements = $('body');
        }

        // loop through the affectedElements
        daContext.affectedElements.each(function (idx, el) {
            affectedElement = $(el);
            // check for spinner or  on the element 
            if (affectedElement.children(NATIVE_SPINNER_SELECTOR).length > 0 || affectedElement.children(CUSTOM_SPINNER_SELECTOR).length > 0 || affectedElement.hasClass(REGION_HAS_OVERLAY)) {
                return;
            }

            if(config.spinnerType != 'none'){
                // create the spinner
                spinner = apex.util.showSpinner(affectedElement, {
                    fixed: config.overlayType == 'on-page',
                    spinnerClass: config.spinnerClass,
                    alert: config.accessText
                });
            }
            
            if (config.spinnerType === 'custom') {
                let newSpinner = addCustomSpinner(config.id, config.spinnerHTML, config.spinnerCSS, spinner);
                spinner[0].parentNode.replaceChild(newSpinner[0], spinner[0]);
                spinner = newSpinner;
            } else if (config.spinnerType.includes('def-')) {
                let styleID = 'fos-spinner-actions-custom-css-' + config.id;
                let spinnerCls = config.spinnerType.substr(4);
                spinner[0].classList.add('fos-sa-spinner', 'fos-sa-' + spinnerCls + '-' + config.id);

                if ($('#' + styleID).length < 1) {
                    let customStyle = '<style id="fos-spinner-actions-custom-css-' + config.id + '">' + createStyle(spinnerCls, config.spinnerColor, config.id) + '</style>';
                    $('head').append(customStyle);
                }

                spinner.empty();
                let spinnerHTML = createMarkup(spinnerCls);
                $(spinnerHTML).prependTo(spinner);
            } else if (config.spinnerType === 'default') {
                spinner.addClass('fos-sa-spinner-default');
                if (config.spinnerColor && config.spinnerColor != '') {
                    spinner.css('background-color', config.spinnerColor);
                }
            }

            // create a unique id for the spinner instance (daContext.id + element index)
            // (need it to associate it with the overlay element)
            id = config.id + '_' + idx;
            if(spinner){
                spinner.attr('id', id);
            }
            
            // add overlay, if neccessary
            if (config.overlayType != 'none') {
                if(spinner){
                    spinner.addClass(SPINNER_WITH_OVERLAY);
                };
                me.addOverlay(affectedElement, config, id);
            }

            if (config.overlayType != 'on-page') {
                affectedElement.addClass(REGION_HAS_SPINNER);
            }
        });
    };

    let createStyle = function (type, color, id) {
        let selector = '.fos-sa-spinner.fos-sa-' + type + '-' + id + ' .fos-sa-' + type;
        if (['circle', 'ring', 'ellipsis', 'grid'].includes(type)) {
            selector += ' div ';
        } else if (type === 'dual-ring' || type === 'hourglass') {
            selector += '::after';
        } else if (type === 'roller') {
            selector += ' div::after';
        } else if (type === 'heart') {
            selector += ' div, .fos-sa-spinner.fos-sa-heart-' + id + ' .fos-sa-heart div::before, .fos-sa-spinner.fos-sa-heart-' + id + ' .fos-sa-heart div::after ';
        }
        let style;
        if (['circle', 'heart', 'roller', 'ellipsis', 'grid'].includes(type)) {
            style = 'background: ' + color + ';';
        } else if (type === 'ring') {
            style = 'border-top-color: ' + color + ';';
        } else {
            style = 'border-top-color: ' + color + '; border-bottom-color: ' + color + ';';
        }

        return selector + '{ ' + style + '}';
    };

    let createMarkup = function (type) {
        const childCount = {
            'circle': 1,
            'dual-ring': 0,
            'heart': 1,
            'ring': 4,
            'roller': 8,
            'ellipsis': 4,
            'hourglass': 0,
            'grid': 9
        };
        let spinnerCls = 'fos-sa-' + type;
        let parent = document.createElement('div');
        parent.classList.add(spinnerCls);
        for (let i = 0; i < childCount[type]; i++) {
            parent.appendChild(document.createElement('div'));
        }
        return parent;
    };

    let removeSpinner = function (daContext, config) {
        let spinnerElements, spinnerEl, spinnerId;
        let me = this;

        // set to default
        if (!daContext.action.affectedElementsType) {
            daContext.affectedElements = $('body');
        }

        daContext.affectedElements.each(function (idxx, el) {
            // find the splitter element    
            spinnerElements = $(el).children(NATIVE_SPINNER_SELECTOR);
            if (spinnerElements.length == 0) {
                spinnerElements = $(el).children(CUSTOM_SPINNER_SELECTOR);
            }
            // return if not found
            if (spinnerElements.length == 0 && !$(el).hasClass(REGION_HAS_OVERLAY)) {
                return;
            }

            spinnerElements.each(function (sIdx, sEl) {
                // get the spinner element
                spinnerEl = $(sEl);
                // save the id
                spinnerId = spinnerEl.attr('id');
                // remove parent class if any
                spinnerEl.parent().removeClass(REGION_HAS_SPINNER);
                // remove the element
                spinnerEl.remove();
                // using the splitter id, remove the overlay
                me.removeOverlay(spinnerId, spinnerEl.hasClass(SPINNER_WITH_OVERLAY));
            });

            // get the overlay element id
            let overlayEl = $(el).children('.' + OVERLAY_REGION_STYLE);
            if(overlayEl.length > 0){
                me.removeOverlay(overlayEl.attr('data-spinner-id'), false);
            }

        });
    };

    let convertDefault = function (daContext, config) {
        apex.debug.info('daContext', daContext);
        apex.debug.info('config', config);
        let me = this;
        apex.util.showSpinner = function (pContainer, pOptions) {
            var lSpinner$, lLeft, lTop, lBottom, lYPosition, lYOffset,
                out = apex.util.htmlBuilder(),
                lOptions = $.extend({
                    alert: apex.lang.getMessage("APEX.PROCESSING"),
                    spinnerClass: ""
                }, pOptions),
                lContainer$ = (pContainer && !lOptions.fixed) ? $(pContainer) : $("body"),
                lWindow$ = $(window),
                lContainer = lContainer$.offset(),
                lViewport = {
                    top: lWindow$.scrollTop(),
                    left: lWindow$.scrollLeft()
                };

            if (config.spinnerType.includes('def-')) {
                let styleID = 'fos-spinner-actions-custom-css-' + config.id;
                let spinnerCls = config.spinnerType.substr(4);
                if ($('#' + styleID).length < 1) {
                    let toAppend = '<style id="fos-spinner-actions-custom-css-' + config.id + '">' + createStyle(spinnerCls, config.spinnerColor, config.id) + '</style>';
                    $('head').append(toAppend);
                }
                lSpinner$ = $('<span class="fos-sa-spinner u-Processing" role="alert"></span>');
                lSpinner$.append($(createMarkup(spinnerCls)));
                lSpinner$.addClass('fos-sa-' + spinnerCls + '-' + config.id);
            } else if (config.spinnerType == 'custom') {
                lSpinner$ = addCustomSpinner(config.id, config.spinnerHTML, config.spinnerCSS);
            } else {
                // The spinner markup
                out.markup("<span")
                    .attr("class", "u-Processing" + (lOptions.spinnerClass ? " " + lOptions.spinnerClass : ""))
                    .attr("role", "alert")
                    .markup(">")
                    .markup("<span")
                    .attr("class", "u-Processing-spinner")
                    .markup(">")
                    .markup("</span>")
                    .markup("<span")
                    .attr("class", "u-VisuallyHidden")
                    .markup(">")
                    .content(lOptions.alert)
                    .markup("</span>")
                    .markup("</span>");

                // And render and position the spinner and overlay
                lSpinner$ = $(out.toString());
            }

            lSpinner$.appendTo(lContainer$);

            if (lOptions.fixed) {
                lTop = (lWindow$.height() - lSpinner$.height()) / 2;
                lLeft = (lWindow$.width() - lSpinner$.width()) / 2;
                lSpinner$.css({
                    position: "fixed",
                    top: lTop + "px",
                    left: lLeft + "px"
                });
            } else {
                // Calculate viewport bottom and right
                lViewport.bottom = lViewport.top + lWindow$.height();
                lViewport.right = lViewport.left + lWindow$.width();

                // Calculate container bottom and right
                lContainer.bottom = lContainer.top + lContainer$.outerHeight();
                lContainer.right = lContainer.left + lContainer$.outerWidth();

                // If top of container is visible, use that as the top, otherwise use viewport top
                if (lContainer.top > lViewport.top) {
                    lTop = lContainer.top;
                } else {
                    lTop = lViewport.top;
                }

                // If bottom of container is visible, use that as the bottom, otherwise use viewport bottom
                if (lContainer.bottom < lViewport.bottom) {
                    lBottom = lContainer.bottom;
                } else {
                    lBottom = lViewport.bottom;
                }
                lYPosition = (lBottom - lTop) / 2;

                // If top of container is not visible, Y position needs to add an offset equal hidden container height,
                // this is required because we are positioning in the container element
                lYOffset = lViewport.top - lContainer.top;
                if (lYOffset > 0) {
                    lYPosition = lYPosition + lYOffset;
                }

                lSpinner$.position({
                    my: "center",
                    at: "left+50% top+" + lYPosition + "px",
                    of: lContainer$,
                    collision: "fit"
                });
            }

            // add overlay, if neccessary
            if (config.overlayType != 'none') {
                // check for spinners
                let numOfSpinners = $('.fos-sa-spinner.u-Processing').length;

                let id = config.id + '_' + parseFloat(numOfSpinners + 1);
                lSpinner$.attr('id', id);

                me.addOverlay(lContainer$, config, id);

                lSpinner$.on('remove', function (e) {
                    me.removeOverlay(id, config.overlayType == 'on-page');
                });
            }

            return lSpinner$;
        };
    };

    let removeOverlay = function (id, onPage) {
        // find the overlay element
        let overlayEl = $('[data-spinner-id="' + id + '"');
        if (overlayEl.length != 0) {
            // remove the 'has-overlay' class from the parent el /applies only to regions/
            overlayEl.parent().removeClass(REGION_HAS_OVERLAY);
            // remove the overlay
            overlayEl.remove();
            // add the scrolling to the page
            if (onPage) {
                $('body').css({ 'overflow': 'scroll' });
            }
        }
    };

    let addOverlay = function (el, config, id) {
        // check whether there's an overlay element on the body already
        let pageOverlay = $('.' + OVERLAY_BODY_STYLE);
        // if so, return
        if (pageOverlay.length > 0) {
            return;
        }
        // calculate the opacity
        if (config.overlayOpacity < 0) {
            config.overlayOpacity = 0;
        } else if (config.overlayOpacity > 100) {
            config.overlayOpacity = 100;
        }
        let opacity = parseInt(config.overlayOpacity || 50) / 100;

        let computedStyle = getComputedStyle(el[0]);
        let elInnerHeight = parseInt(computedStyle.height) - (parseInt(computedStyle.paddingTop) + parseInt(computedStyle.paddingBottom));
        let elInnerWidth = parseInt(computedStyle.width) - (parseInt(computedStyle.paddingLeft) + parseInt(computedStyle.paddingRight));

        // create the overlay element
        // the data-spinner-id attribute will be used to associate it with the spinner
        let overlayEl = $('<div style="height:' + elInnerHeight + 'px;width:' + elInnerWidth + 'px;background:' + config.overlayColor + ';opacity:' + opacity + '" data-spinner-id="' + id + '"></div>');
        // set the classes
        overlayEl.attr('class', config.overlayType == 'on-page' ? OVERLAY_BODY_STYLE : OVERLAY_REGION_STYLE);
        // add it to the element
        overlayEl.prependTo(el);
        // set the css class on the region
        el.addClass(REGION_HAS_OVERLAY);

        // prevent scrolling, if the overlay is on the page
        if (config.overlayType == 'on-page') {
            $('body').css({ 'overflow': 'hidden' });
        }
    };

    return {
        showSpinner,
        removeSpinner,
        convertDefault,
        addOverlay,
        removeOverlay
    };

})(apex.jQuery);
