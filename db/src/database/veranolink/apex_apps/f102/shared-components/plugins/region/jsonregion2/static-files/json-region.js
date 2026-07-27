/*

APEX JSON-region plugin
Copyright Uwe Simon 2023

*/

"use strict";

    /*
     * initialize the JSON-region plugin, call form inside PL/SQL when plugin ist initialized
     */
function initJsonRegion( pRegionId, pName, pAjaxIdentifier, pOptions) {

  console.log('test');
  console.dir(apex.util.toArray(['a','b','c']));
  // pOptions.readonly=true;
        // Hacks to make the fields of json-region work like regular APEX-item-fields 
  function apexHacks(){
    // Hack to attach all Handler to the fields in the json-region  
    apex.item.attach($('#' + pRegionId));
          // hack to support floating lables for universal-thema 42
    if(apex.theme42){
      apex.debug.info('Theme42 patch');
      apex.event.trigger(apex.gPageContext$, 'apexreadyend');
    }
  }

  const C_DELIMITER         = '_'                  // delimiter for path of nested objects
  const C_APEX_SWITCH       = 'switch';            // itemtype switch
  const C_JSON_REGION_CLASS = 'json-region-class'; // Class added to input items in json-region
  let   gData = {};  // holds the JSON-data as an object hierarchie

  function deepMerge(target, source) {
    for (const key in source) {
      if (source.hasOwnProperty(key)) {
        if (typeof source[key] === "object") {
          if (typeof target[key] !== "object" || Array.isArray(target[key])) {
            target[key] = Array.isArray(source[key]) ? [] : {};
          }
          deepMerge(target[key], source[key]);
        } else {
          target[key] = source[key];
        }
      }
    }
  }

    // set the required attribute and UI marker
  function setRequired(dataitem, mode){
    let item = $('#' + dataitem);
    item.prop("required",mode);
    if(mode==true){
      item.closest(".t-Form-fieldContainer").addClass("is-required");
    } else {
      item.closest(".t-Form-fieldContainer").removeClass("is-required");
    }
  }
    // convert item-value into json-value
  function itemValue2Json(schema, value){
    let l_value = value;
    if(value!=null){
      try{
        switch(schema.type){
          case 'string':
            switch(schema.format){
              case 'date':
                l_value = apex.date.toISOString(apex.date.parse(value, apex.locale.getDateFormat())).substring(0,10);
              break;
              case 'date-time':
                l_value = apex.date.toISOString(apex.date.parse(value, apex.locale.getDateFormat()+' HH24:MI:SS'));
              break;  
            }
            l_value = l_value.length>0?l_value:null;
          break;  
          case 'boolean':
            l_value = (value=="Y");
          break;
          case 'integer':
          case 'number':
            if(schema.apex &&schema.apex.format){
              l_value = apex.locale.toNumber(value, schema.apex.format);
            } else {
              l_value = apex.locale.toNumber(value);
            }
          break;  
        }
      } catch(e){
        apex.debug.error('Invalid input data', schema.apex.format, value, e);
      }
    }
    return l_value;
  }
    // convert json-value into item-value
  function jsonValue2Item(schema, value){
    let l_value = value;
    if(value){
    try {    
      switch(schema.type){
        case 'string':
          switch(schema.format){
            case 'date':
              l_value = apex.date.format(apex.date.parse(value,'YYYY-MM-DD'), apex.locale.getDateFormat());
            break;
            case 'date-time':
              l_value = apex.date.format(apex.date.parse(value,'YYYY-MM-DDTHH24:MI'), apex.locale.getDateFormat()+' HH24:MI:SS');
            break;  
          }
        break;  
        case 'boolean':
          l_value = (value?"Y":"N");
        break;
        case 'integer':
        case 'number':
         l_value = apex.locale.formatNumber(value, schema.apex && schema.apex.format ||null);
        break;
      }
      } catch(e){
        apex.debug.error('Invalid JSON-data', value, e);
      }
    }   
    return(l_value);
  }

    // attach the generated fields to APEX and fill with data
  function attachFields(dataitem, previtem, schema, data){ 
    apex.debug.trace(">>jsonRegion.attachFields", dataitem, schema, data);
    schema.apex = schema.apex || {};
    let l_value = jsonValue2Item(schema, data);
    switch(schema.type){
    case 'object':
      if(schema.properties){
        data = data ||{};
        for(let [l_name, l_item] of Object.entries(schema.properties)){
          attachFields(dataitem + C_DELIMITER +l_name, dataitem, l_item, data[l_name]);
        }
      }
    break;
    case 'array':   // TODO: not yet implemented
      console.warn('ARRAY', 'not yet implemented');
      apex.widget.checkboxAndRadio('#'+ dataitem,'checkbox');
      apex.item(dataitem).setValue(l_value||[]);
    case 'null':
    break;

    case 'string':
      if(!pOptions.readonly){
        if(schema.apex.itemtype=='radio'){
          apex.widget.checkboxAndRadio('#'+ dataitem,'radio');
        } else {
          apex.item.create(dataitem, {});            
        }
        apex.item(dataitem).setValue(l_value);
      }
    break;
    case 'boolean':
    if(schema.apex.itemtype==C_APEX_SWITCH){
      apex.widget.yesNo(dataitem, 'SWITCH_CB'); 
      apex.item(dataitem).setValue(l_value);
      if(pOptions.readonly) {
        apex.item(dataitem).disable();
      }  
    }
    break;
    case 'number':
    case 'integer':
      if(schema.apex.itemtype=='starrating'){
        apex.widget.starRating(dataitem, {showClearButton: false, numStars: schema.maximum}); 
        apex.item(dataitem).setValue(l_value);
      } else {       
        if(!pOptions.readonly){
          apex.item.create(dataitem, {});
          apex.item(dataitem).setValue(l_value);
        }
      }
    break;
    default:
        if(!'const' in schema) {  // a const value does n't need a type, 
          apex.debug.error('item with undefined type', dataitem, schema.type);
        }
    break;
    }
/*
    if(isWidget && (schema.apex.readonly || pOptions.readonly)){
        apex.item(dataitem).disable();
    }
*/
    if(Array.isArray(schema.dependentRequired)) { 
            // the item has dependent items, so add callback on data change
        for(const item of schema.dependentRequired) {
          let l_item = previtem + C_DELIMITER + item
          setRequired(l_item, l_value && l_value.length>0);
        }
        $("#" + dataitem).on('change', function(){
          console.warn('clicked', dataitem, $(this).val() );
          for(const item of schema.dependentRequired) {
            let l_item = previtem + C_DELIMITER + item
            let l_value = $(this).val();
            console.warn('depends', l_item, l_value);
            setRequired(l_item, l_value && l_value.length>0);
          };
        });
    }
    apex.debug.trace("<<jsonRegion.attachFields");
  }

    // retrieve data for UI-fields and build JSON
  function getData(dataitem, schema){ 
    apex.debug.trace(">jsonRegion.getData", dataitem, schema);
    let l_json = {};
    switch(schema.type){
    case 'object':
      if(schema.properties){
        for(let [l_name, l_item] of Object.entries(schema.properties)){
          l_json[l_name]=getData(dataitem + C_DELIMITER +l_name, l_item);
        }
      }
    break;
    case 'null':
      l_json = null;
    break;
    case 'array': {  // currently only support for a "simple array" with checkboxes
      let l_data = apex.item(dataitem).getValue();
      l_json = itemValue2Json(schema, l_data);
    }
    break;
    case 'string':
    case 'number':
    case 'integer':
    case 'boolean':{
      let l_data = apex.item(dataitem).getValue();
      let l_value = itemValue2Json(schema, l_data);
      if(l_value!=null){
        l_json = l_value;
      } else {
        l_json = null;
      }
    }
    break;
    default:
      if('const' in schema) {  // a const doesn't have a item in the UI
        l_json = schema.const;
      }
    break;
    }
    apex.debug.trace("<jsonRegion.getData", l_json);
    return(l_json);
  }

     // propagate required/$refs into properties/items
  function propagateProperties(schema, level){ 
    apex.debug.trace(">>jsonRegion.propagateProperties", level, schema);
    level++;
    if(level>20){
      apex.debug.error('propagateProperties recursion', level, 'to deep')
      return;
    }
      // first resolve the $ref references
    if(schema['$ref']){
      let jsonpath=schema['$ref'];
      if(jsonpath.substring(0,2) =='#/'){
        let getValue = (o, p) => p.replace('#/','').split('/').reduce((r, k) => r[k], o);
        try{
          let newSchema = getValue(pOptions.schema, jsonpath);
          delete(schema['$ref']);
          Object.assign(schema, newSchema);
/*          
          let tmpSchema ={};
          Object.assign(tpmSchema, newSchema);
          deepMerge(tmpSchema, schema);
*/
          console.dir(schema);
        } catch(e){
          apex.debug.error('$defs not found: ', jsonpath);
        }
      }
    }
        // propagate the dependentRequired directly to the properties 
    if(schema.type=='object' && schema.dependentRequired){
      for(let [l_name, l_item] of Object.entries(schema.dependentRequired)){
        try{
          schema.properties[l_name].dependentRequired = l_item;
        }catch(e){
          apex.debug.error('rependentRequired not found: ', l_name);            
        }
      }
    }

    switch (schema.extendedType) {   // Oracle-spcific extension, convet into json-schema repesnetation
    case 'date':
      schema.type="string";
      schema.format= schema.format|| "date"; // do not overwrite existing formats
    break;
    case 'timestamp':
      schema.type="string";
      schema.format=schema.format||"date-time";
    break;
    }

        // set apex.formats
    schema.apex = schema.apex||{};

    switch(schema.type){
      case 'number':
        schema.apex.format = (schema.apex.format=='currency')?'FML999G999G999G999G999D99':(schema.apex.format?schema.apex.format:'');
      break;
      case 'integer':
        schema.apex.format = (schema.apex.format=='currency')?'FML999G999G999G999G999':(schema.apex.format?schema.apex.format:'99999999999999999999999');
      break;
      case 'string':
        switch(schema.format){
         case 'date':
           schema.apex.format = (schema.apex.format?schema.apex.format:apex.locale.getDateFormat());
         break;
         case 'date-time':
           schema.apex.format = (schema.apex.format?schema.apex.format:apex.locale.getDateFormat() + ' HH24:MI:SS');
         break;   
        }
      break;    
    }
        // propagate required to each properties
    if(Array.isArray(schema.required)){
      for(let l_item of schema.required){
        if(schema.properties && schema.properties[l_item]){
          schema.properties[l_item].required_=true;
        }
        if(schema.items && schema.items[l_item]){
          schema.items[l_item].required_=true;
        }
      }
    }

    for(let [l_name, l_item] of Object.entries(schema.properties||{})){
      propagateProperties(l_item, level);
    }

    if(schema.items){  // there is an item definition, process this
      propagateProperties(schema.items, level);
    }

    apex.debug.trace("<<jsonRegion.propagateProperties");
  }

    // generate the UI-item for a radio/checkbox property
  function generateForSelect(level, schema, data, prefix, name, startend, checkbox){
    let l_html='';
    apex.debug.trace(">>jsonRegion.generateForSelect", level, schema, data, prefix, name, startend, checkbox);
    l_html=apex.util.applyTemplate(`
<div tabindex="-1" id="#ID#" aria-labelledby="#ID#_LABEL" #REQUIRED# class="#CLASS# #TYPE#_group apex-item-group apex-item-group--rc apex-item-#TYPE#" role="group">
`,
                                                {
                                                    placeholders: {
                                                      "TYPE":  checkbox?'checkbox':'radio'
                                                   }
                                                });
    let l_nr=0;
    for(const l_value of schema.enum){
      l_html += apex.util.applyTemplate(`
  <div class="apex-item-option">
    <input type="#TYPE#" id="#ID#_#NR#" name="#ID#" data-display="#VALUE#" value="#VALUE#" #REQUIRED# aria-label="#VALUE#" class="#CLASS#">
    <label class="u-#TYPE#" for="#ID#_#NR#" aria-hidden="true">#VALUE#</label>
  </div>
`,
                                                {
                                                    placeholders: {
                                                      "TYPE":  checkbox?'checkbox':'radio',
                                                      "VALUE": l_value,
                                                      "NR":    l_nr++
                                                   }
                                                });
    }
    l_html += `
</div>
`;
    apex.debug.trace("<<jsonRegion.generateForSelect");
    return(l_html);
  }

    // generate the UI-item for a numeric property
  function generateForString(level, schema, data, prefix, name, startend){
    let l_html='';
    apex.debug.trace(">>jsonRegion.generateForString", level, schema, data, prefix, name, startend);
    if(pOptions.readonly){
      l_html='<span id="#ID#_DISPLAY" #REQUIRED# class="display_only apex-item-display-only" data-escape="true">#VALUE#</span>';
    } else {
      if(Array.isArray(schema.enum)){
        if(schema.apex && schema.apex.itemtype=='radio'){
          l_html= generateForSelect(level, schema, data, prefix, name, startend, false);
/*          
          l_html=`
<div tabindex="-1" id="#ID#" aria-labelledby="#ID#_LABEL" class="#CLASS# radio_group apex-item-group apex-item-group--rc apex-item-radio" role="group">
`;
          let l_nr=0;
          for(const l_value of schema.enum){
            l_html += apex.util.applyTemplate(`
  <div class="apex-item-option">
    <input type="radio" id="#ID#_#NR#" name="#ID#" data-display="#VALUE#" value="#VALUE#" required="" aria-label="#VALUE#" class="#CLASS#">
    <label class="u-radio" for="#ID#_#NR#" aria-hidden="true">#VALUE#</label>
  </div>
`,
                                                {
                                                    placeholders: {
                                                      "VALUE": l_value,
                                                      "NR":    l_nr++
                                                   }
                                                });
          }
          l_html += `
</div>
`;
*/
        } else {
          l_html = `
<select id="#ID#" name="#ID#" #REQUIRED# class="#CLASS# selectlist apex-item-select" data-native-menu="false" size="1">
`;           
          if(!schema.required_) l_html+='<option value=""></option>';
          for(const l_value of schema.enum){
            l_html += apex.util.applyTemplate(`
  <option value="#VALUE#">#VALUE#</option>
`,
                                                {
                                                    placeholders: {
                                                      "VALUE": l_value
                                                   }
                                                });
          }
          l_html +=
`
</select>
`;
        }
      } else {
        switch(schema.format){
        case "email":
          l_html = `
<input type="email" id="#ID#" name="#ID#" #REQUIRED# #PATTERN# class="#CLASS# text_field apex-item-text" size="32" #MINLENGTH# #MAXLENGTH# data-trim-spaces="#TRIMSPACES#" aria-describedby="#ID#_error">
`;
        break;
        case "uri":
          l_html = `
<input type="url" id="#ID#" name="#ID#" #REQUIRED# #PATTERN# class="#CLASS# text_field apex-item-text" size="32" #MINLENGTH# #MAXLENGTH# data-trim-spaces="#TRIMSPACES#" aria-describedby="#ID#_error">
`;
        break;
        case "date":
          l_html = `
<a-date-picker id="#ID#" #REQUIRED# change-month="true" change-year="true" display-as="popup" display-weeks="number"  #MIN# #MAX# previous-next-distance="one-month" show-days-outside-month="visible" show-on="focus" today-button="true" format="#FORMAT#" valid-example="#EXAMPLE#" year-selection-range="5" class="apex-item-datepicker--popup">
  <input aria-haspopup="dialog" class="#CLASS# apex-item-text apex-item-datepicker" name="#ID#" size="20" maxlength="20" type="text" id="#ID#_input" required="" aria-labelledby="#ID#_LABEL" maxlength="255" value="#VALUE#">
  <button aria-haspopup="dialog" aria-label="#INFO#" class="a-Button a-Button--calendar" tabindex="-1" type="button" aria-describedby="#ID#_LABEL" aria-controls="#ID#_input">
    <span class="a-Icon icon-calendar">
    </span>
  </button>
</a-date-picker>
`;
        break;
        case "date-time":
          l_html = `
<a-date-picker id="#ID#" #REQUIRED# change-month="true" change-year="true" display-as="popup" display-weeks="number" #MIN# #MAX# previous-next-distance="one-month" show-days-outside-month="visible" show-on="focus" show-time="true" time-increment-minute="15" today-button="true" format="#FORMAT#"valid-example="#EXAMPLE#" year-selection-range="5" class="apex-item-datepicker--popup">
  <input aria-haspopup="dialog" class="#CLASS# apex-item-text apex-item-datepicker" name="#ID#" size="30" maxlength="30" type="text" id="#ID#_input" required="" aria-labelledby="#ID#_LABEL" maxlength="255" value="#VALUE#">
  <button aria-haspopup="dialog" aria-label="#INFO#" class="a-Button a-Button--calendar" tabindex="-1" type="button" aria-describedby="#ID#_LABEL" aria-controls="#ID#_input">
    <span class="a-Icon icon-calendar-time">
    </span>
  </button>
</a-date-picker>
`;
        break;
        default:
          if(!schema.maxLength || schema.maxLength<=pOptions.textareawidth){
            l_html = `
<input type="text" id="#ID#" name="#ID#" #REQUIRED# #PATTERN# class="#CLASS# text_field apex-item-text" size="32" #MINLENGTH# #MAXLENGTH# data-trim-spaces="#TRIMSPACES#" aria-describedby="#ID#_error">
`;
          }else { 
            l_html = `
<div class="apex-item-group apex-item-group--textarea">
  <textarea name="#NAME#" rows="#ROWS#" cols="100" id="#ID#" class="#CLASS# textarea apex-item-textarea" data-resizable="true" style="resize: both;">#QUOTEVALUE#</textarea>
</div>
 `;
          }
        break;
        }
      }
    }
    apex.debug.trace("<<jsonRegion.generateForString");
    return(l_html);
  };


    // generate the UI-item for a numeric property
  function generateForNumeric(level, schema, data, prefix, name, startend){
    let l_html='';
    apex.debug.trace(">>jsonRegion.generateForNumeric", level, schema, data, prefix, name, startend);
          if(schema.apex && schema.apex.itemtype=="starrating"){
            if(pOptions.readonly){
              l_html = `
<div id="#ID#" class="a-StarRating apex-item-starrating">
  <div class="a-StarRating">
    <input type="text" aria-labelledby="#ID#_LABEL" id="#ID#_INPUT" disabled value="#VALUE#" name="#ID" class="#CLASS# u-vh is-focusable" role="spinbutton" aria-valuenow="#VALUE#" aria-valuemax="#MAX#" aria-valuetext="#VALUE#"> 
    <div class="a-StarRating-stars"> 
    </div>
  </div>
</div>
`;
            } else {
              l_html = `
<div id="#ID#" class="a-StarRating apex-item-starrating">
  <div class="a-StarRating">
    <input type="text" aria-labelledby="#ID#_LABEL" id="#ID#_INPUT" value="#VALUE#" name="#ID" class="#CLASS# u-vh is-focusable" role="spinbutton" aria-valuenow="#VALUE#" aria-valuemax="#MAX#" aria-valuetext="#VALUE#"> 
    <div class="a-StarRating-stars"> 
    </div>
  </div>
</div>
`;
            }
          } else {
            if(pOptions.readonly){
              l_html='<span id="#ID#_DISPLAY" #REQUIRED# class="display_only apex-item-display-only" data-escape="true">#VALUE#</span>';
            } else {
              l_html = `
<input type="text" id="#ID#" name="#ID#" #REQUIRED# class="#CLASS# number_field apex-item-text apex-item-number" size="30" #MIN# #MAX# data-format="#FORMAT#" inputmode="decimal" style="text-align:start">
`;
          }
        }

    apex.debug.trace("<<jsonRegion.generateForNumeric");
    return(l_html);
  };

    // generate the UI-item for a boolean property
  function generateForBoolean(level, schema, data, prefix, name, startend){
    let l_html='';
    apex.debug.trace(">>jsonRegion.generateForBoolean", level, schema, data, prefix, name, startend);
    if(schema.apex && schema.apex.itemtype=="switch"){
      l_html = `
<span class="a-Switch">
  <input type="checkbox" id="#ID#" name="#ID#" #DISABLED# class="#CLASS#" value="Y" data-on-label="On" data-off-value="N" data-off-label="Off">
  <span class="a-Switch-toggle"></span>
</span>
`;    
    } else {
      l_html = `
<div class="apex-item-single-checkbox">
  <input type="hidden" name="#ID#" class="#CLASS#" id="#ID#_HIDDENVALUE" value="#VALUE#">
  <input type="checkbox" #CHECKED# #DISABLED# #REQUIRED# id="#ID#" aria-label="#LABEL#" data-unchecked-value="N" value="Y">
  <label for="#ID#" id="#ID#_LABEL" class=" u-checkbox" aria-hidden="true">#LABEL#</label>
</div>
`;    
    }
    apex.debug.trace("<<jsonRegion.generateForBoolean");
    return (l_html);
  }

    // generate UI for type="array"
  function generateForArray(level, schema, data, prefix, name, startend){
    let l_html='';
    apex.debug.trace(">>jsonRegion.generateForArray", level, schema, data, prefix, name, startend);
    if(schema.type =='string' && Array.isArray(schema.enum)){
      l_html = generateForSelect(level, schema, data, prefix, name, startend, true);
    } else {
      console.warn('ARRAY not jet implemented', level, schema, data, prefix, name, startend);
    }
    apex.debug.trace("<<jsonRegion.generateForArray");    
    return(l_html);
  }

    // generate UI for type="object" and simple types
  function generateForObject(level, schema, data, prefix, name, startend){
      let l_html='';
      let l_input='';
      let l_wrappertype ='';
      
      apex.debug.trace(">>jsonRegion.generateForObject", level, schema, data, prefix, name, startend);

      if(schema.apex && schema.apex.newRow) { // current field should start at a new row
          l_html += `
</div>
<div class="row jsonregion">
`;
      }

      switch(schema.type){
        case "array":
          l_wrappertype = 'apex-item-wrapper--checkbox';
          l_input = generateForArray(level+1, schema.items, (prefix?prefix+C_DELIMITER:'')+name, name, startend);
        break;
        case "object": // an object, so generate all of its properties
          data = data ||'{}';
          let l_row=1;
          if(pOptions.headers && level>0){
            let label = name.toLowerCase()
                      .split(/ |\-|_/)
                      .map((s) => s.charAt(0).toUpperCase() + s.substring(1))
                      .join(' ');

            l_html += apex.util.applyTemplate(`
</div>
<div class="row jsonregion">
  <div class="t-Region-header">
    <div class="t-Region-headerItems t-Region-headerItems--title">
      <h2 class="t-Region-title" id="R17715610701691854_heading" data-apex-heading="">#LABEL#</h2>
    </div>
   </div>
</div>
<div class="row jsonregion">
 `,
                                    { placeholders: {"LABEL":       label
                                                    }
                                    });
          }
          for(let [l_name, l_item] of Object.entries(schema.properties||{})){
            startend = 0; //l_row==1?-1:(l_row>=Object.keys(schema.properties).length?1:0);
            l_html += generateForObject(level+1, l_item, data[l_name], (prefix?prefix+C_DELIMITER:'')+name, l_name, startend);
            l_row++;
          }
          if(pOptions.headers && level>0){
              l_html += `
</div>
<div class="row jsonregion"">
`;
          }
        break;
        case 'string':
          l_input = generateForString(level, schema, data, prefix, name, startend);

          switch(schema.format){
          case "email":
            l_wrappertype = 'apex-item-wrapper--text-field';
          break;
          case "uri":
            l_wrappertype = 'apex-item-wrapper--text-field';
          case "date":
            l_wrappertype='apex-item-wrapper--date-picker-apex apex-item-wrapper--date-picker-apex-popup';
          break;
          case "date-time":
            l_wrappertype='apex-item-wrapper--date-picker-apex apex-item-wrapper--date-picker-apex-popup';
          break;
          default:
            if(Array.isArray(schema.enum)) {    // an enum array
              l_wrappertype = (schema.apex && schema.apex.itemtype=='radio')?'apex-item-wrapper--radiogroup':'apex-item-wrapper--select-list';
            } else if(!schema.maxLength || schema.maxLength<=pOptions.textareawidth){ //short string textfield
              l_wrappertype = 'apex-item-wrapper--text-field';
            } else {    // long string textarea
              l_wrappertype = 'apex-item-wrapper--textarea';
            }
          break;
          }          
        break;

        case 'number':
        case 'integer':
          l_input = generateForNumeric(level, schema, data, prefix, name, startend);
          if(schema.apex && schema.apex.itemtype=="starrating"){
            l_wrappertype = 'apex-item-wrapper--star-rating';
          } else {
            l_wrappertype = 'apex-item-wrapper--number-field';              
          }
        break;
        case 'boolean':
          l_input = generateForBoolean(level, schema, data, prefix, name, startend);
          if(schema.apex && schema.apex.itemtype==C_APEX_SWITCH){
            l_wrappertype='apex-item-wrapper--yes-no';
          }else {
            l_wrappertype='apex-item-wrapper--single-checkbox';
          }

       
        break;
        case undefined:  // no type, so do nothing
          if(!'const' in schema){ // a const doesn't need a type
            apex.debug.error('schema.type is undefined');
          }
          l_input='';
        break
        case 'null':
          l_input ='';
        break;    
        default:
          l_input='<span id="#ID#_DISPLAY" #REQUIRED# class="display_only apex-item-display-only" data-escape="true">not implemented type:' + schema.type + '</span>';
        break;
      }

      if(l_input.length){ // The input item is generated
        let label = '';

        if(schema.apex && schema.apex.label){  // label in "apex" has priority
          label = schema.apex.label;            
        } else {    // generate default label split by " ", "-", "_" single words with 1st uppercase
          label = name.toLowerCase()
                      .split(/ |\-|_/)
                      .map((s) => s.charAt(0).toUpperCase() + s.substring(1))
                      .join(' ');
        }
        l_html += apex.util.applyTemplate(
`
  <div class="col col-#COLWIDTH# apex-col-auto #COLSTARTEND#">
    <div  id="#ID#_CONTAINER" class="t-Form-fieldContainer t-Form-fieldContainer--floatingLabel #ISREQUIRED# i_112918109_0 apex-item-wrapper #WRAPPERTYPE#" >
      <div class="t-Form-labelContainer">
        <label for="#ID#" id="#ID#_LABEL" class="t-Form-label">#TOPLABEL#</label>
      </div>
      <div class="t-Form-inputContainer">
        <div class="t-Form-itemRequired-marker" aria-hidden="true"></div>
        <div class="t-Form-itemWrapper">
` +  l_input +
` 
        </div>
        <div class="t-Form-itemAssistance">
          <span id="#ID#_error_placeholder" class="a-Form-error u-visible" data-template-id="11057037381926250_ET"></span>
          <div class="t-Form-itemRequired" aria-hidden="true">Required</div>
        </div>
      </div>
    </div>
  </div>
`,
                                    { placeholders: {"WRAPPERTYPE": l_wrappertype,
                                                     "COLWIDTH":    (schema.apex&&schema.apex.colSpan?schema.apex.colSpan:pOptions.colwidth),
                                                     "ROWS":        (schema.apex&&schema.apex.lines?schema.apex.lines:5),
                                                     "COLSTARTEND": startend<0?'col-start':(startend>0?'col-end':''),
                                                     "ID":          prefix + C_DELIMITER + name, 
                                                     "NAME":        prefix + C_DELIMITER + name,
                                                     "LABEL":       label,
                                                     "TRIMSPACES":  'BOTH',
                                                     "FORMAT":      schema.apex?schema.apex.format:'',
                                                     "EXAMPLE":     (['date', 'date-time'].includes(schema.format)?jsonValue2Item(schema, apex.date.toISOString(new Date())):''), 
                                                     "MINLENGTH":   schema.minLength?'minlength=' + schema.minLength:'',
                                                     "MAXLENGTH":   schema.maxLength?'maxlength=' + schema.maxLength:'',
                                                     "CLASS":       C_JSON_REGION_CLASS,
                                                     "DISABLED":    '', //(((schema.apex && schema.apex.readonly) || pOptions.readonly)?'disabled':''),
                                                     "TOPLABEL":    (schema.type=='boolean' && !(schema.apex && schema.apex.itemtype=="switch"))?"":label,
                                                     "CHECKED":     schema.type=='boolean' && data?"checked":"",
                                                     "PATTERN":     schema.pattern?'pattern="'+schema.pattern+'"':"",  
                                                     "REQUIRED":    schema.required_?'required=""':"",
                                                     "ISREQUIRED":  schema.required_?'is-required':"",
                                                     "MIN":         ("minimum" in schema)?(['date', 'date-time'].includes(schema.format)?'min':'data-min')+'='+schema.minimum:"",
                                                     "MAX":         ("maximum" in schema)?(['date','date-time'].includes(schema.format)?'min':'data-max')+ '='+schema.maximum:"",
                                                     "VALUE":       jsonValue2Item(schema, data)||'',
                                                     "QUOTEVALUE":  (schema.type=='string' && data)?apex.util.escapeHTML(data):(data?data:'')
                                                    }
                                    });
        }
        apex.debug.trace("<<jsonRegion.generateForObject");
      return(l_html);
  }


  function refresh() {
    apex.debug.trace(">>jsonRegion.refresh");
    apex.debug.info('Data', gData);
    let l_html = `
<div class="row jsonregion">
` + 
    generateForObject(0, pOptions.schema, gData, '', pOptions.dataitem, 0) + 
`
</div>
`;
        // attach HTML to region
    $("#"+pRegionId).html(l_html);

        // attach the fields to the generated UI
    attachFields(pOptions.dataitem, '', pOptions.schema, gData);
    apex.debug.trace("<<jsonRegion.refresh");
  }

  function showFields(){
        let l_html = `
<div class="row jsonregion">
` + 
  generateForObject(0, pOptions.schema, gData, '', pOptions.dataitem, pOptions.colwidth, 0, 0) + 

`
</div>
`;
        // attach HTML to region
    $("#"+pRegionId).html(l_html);
  }

    // Remove all properties with value NULL to compact the generated JSON
  function removeNulls(data, search){
    if(data) {
      if(Array.isArray(data)){
        data.forEach(function(value, idx){
          removeNulls(data[idx], search); // keep array elements, because position could be meaningfull
        });
    }   else if(typeof(data)=='object'){
        Object.keys(data).forEach(function(value, idx){
          if(removeNulls(data[value], search)===null){  // value is null, so remove the whole key
            delete(data[value]);
          }
        });
        if(!Object.keys(data).length){    // Object is empty now, remove it later
          data=null;
        }
      }
    }
    return(data);
  }

    // bring different formats of data formats in a single one
  function reformatValues(schema, data, read){
    apex.debug.trace(">>reformatValues", schema, data, read); 
    if(data){
      switch(schema.type){
      case "object":
        for(const l_key in schema.properties){
           data[l_key] = reformatValues(schema.properties[l_key], data[l_key], read);
        }
      break;
      case "array":
        for(var i = 0; i < schema.items.length; i++){
           data[i] = reformatValues(schema.items[i], data[i], read);
        }     
      break;
      case "string":
        if(schema.format == 'date-time') { // if T is between date and time replace by blank
          data = data.replace('T',' ');
        }
       break;
       default:
       break;
      } 
      apex.debug.trace("<<reformatValues", data);   
    } 
    return(data);
  }

  apex.debug.trace(">>initJsonRegion", pRegionId, pName, pAjaxIdentifier, pOptions); 

  try{
    pOptions.schema = JSON.parse(pOptions.schema.replace(/\\"/g, '"').replace(/\\n/g, '\n').replace(/\\r/g, '\r').replace(/\\t/g, '\t'));
  } catch(e) {
    apex.debug.error('json-region: schema', e, pOptions.schema);
    pOptions.schema = {};
  }

    // generate the JSON from dataitem-field
  try {
    gData = JSON.parse(apex.item(pOptions.dataitem).getValue()||'{}');
  } catch(e) {
    apex.debug.error('json-region: dataitem', pOptions.dataitem, e, pOptions.schema);
    gData = {};
  }

    // resolve all $refs
  propagateProperties(pOptions.schema, 0);

    // adjust differences in 
  gData = reformatValues(pOptions.schema, gData, true);

  refresh(gData);
  if(pOptions.hide) { // hide the related JSON-item
    apex.item(pOptions.dataitem).hide();
  }

  apex.debug.info('json-region', pRegionId, pName, pOptions, gData);
 
  const callbacks = {
        // Callback for refreshing of the JSON-region, is called by APEX-refresh
      refresh: async function() {
        apex.debug.trace('>>jsonRegion.refresh: ', pRegionId, pAjaxIdentifier, pOptions);
        if(pOptions.isDynamic){
          await apex.server.plugin ( 
            pAjaxIdentifier, 
            { pageItems: pOptions.queryitems}, 
            { success: function( gData ) {
                // for some reason the $defs property is returned as "$defs"
                gData["$defs"]=gData['"$defs"'];
                console.log('WORARROUND $defs');
                console.dir(gData);
                pOptions.schema = gData;
              }
            }  
          );
          
          propagateProperties(pOptions.schema, 0);
          apex.debug.trace(pOptions);
          showFields();
          attachFields(pOptions.dataitem, '', pOptions.schema, gData);
          apexHacks();
        }
        apex.debug.trace('<<jsonRegion.refresh')
      },

        // Callback called by event "apexbeforepagesubmit"
      beforeSubmit: function (){
        apex.debug.trace(">>jsonRegion.beforeSubmit", pRegionId, pOptions.dataitem, pOptions.schema);
        if(!pOptions.readonly){  // do nothing for readonly json-region
          apex.debug.trace('jsonRegion', pOptions);
          let l_json=getData(pOptions.dataitem, pOptions.schema);
          if(pOptions.keepAttributes){
            apex.debug.trace('KEEPATTRIBUTES');
            let l_oldjson = JSON.parse(apex.item(pOptions.dataitem).getValue()||'{}');
            l_json = {
              ...l_oldjson,
              ...l_json
            };
          }
          if(pOptions.removeNulls){
            l_json = removeNulls(l_json);
            apex.debug.trace('removed NULLs', l_json);
          }
          apex.debug.trace('generated JSON', l_json);
          apex.item(pOptions.dataitem).setValue(JSON.stringify(l_json));
        }
        apex.debug.trace("<<jsonRegion.beforeSubmit");
      },

        // Callback called by event "apexpagesubmit"
      submit: function(){
        apex.debug.trace("<>jsonRegion.submit");
          // Hack to remove the dynamically generated item from client-response
        $(".json-region-class").removeAttr('name');
      }
  };

  apex.jQuery(apex.gPageContext$).bind( "apexbeforepagesubmit", function() {
    callbacks.beforeSubmit();
  });
  apex.jQuery( apex.gPageContext$ ).on( "apexpagesubmit", function() {
    callbacks.submit();
  });
    // if reagion already exists destroy it first
  if(apex.region.isRegion(pRegionId)) {
    apex.debug.trace('DESTROY REGION', pRegionId);
    apex.region.destroy(pRegionId);
  }
  apex.region.create( pRegionId, callbacks);
  apex.item.attach($('#' + pRegionId));
  apex.debug.trace("<<initJsonRegion");  
}