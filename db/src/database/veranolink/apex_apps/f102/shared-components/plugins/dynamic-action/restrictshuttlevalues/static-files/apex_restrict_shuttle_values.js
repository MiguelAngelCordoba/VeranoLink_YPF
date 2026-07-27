// APEX Restrict Shuttle Values
// Author: Dick Dral (Detora)
// Version: 1.0
// Date: April 14th, 2017

// global namespace
var apex_restrict_shuttle_values = {

toggleOption: function( option, show ) {
    jQuery( option ).toggle( show );
    if( show ) {
        if( jQuery( option ).parent( 'span.toggleOption' ).length )
            jQuery( option ).unwrap( );
    } else {
        if( jQuery( option ).parent( 'span.toggleOption' ).length == 0 )
            jQuery( option ).wrap( '<span class="toggleOption" style="display: none;" />' );
    }
},
restrict_values: function ( search_item, shuttle_item )
{
  console.log('perform Restrict shuttle values');

  var search = apex.item(search_item).getValue();
  search = search.toLowerCase();

  search_words = search.split(' ');
    console.log('search_words=' , search_words
         );    
    
  var items_hidden = false;
  $('#'+shuttle_item+'_LEFT option').each(
      function() 
      {
         var text = $(this).text().toLowerCase();

         var visible = true;  
         if ( search.length > 0 )
         {
           for ( i = 0; i < search_words.length; i++)
           { 
              if ( text.indexOf(search_words[i]) < 0 ) 
              { visible = false; }
           }
         }

         if ( visible ) 
         {  apex_restrict_shuttle_values.toggleOption(this,true); }
         else
         {  apex_restrict_shuttle_values.toggleOption(this,false); 
            items_hidden = true;
         }

       }
   );  
   if ( items_hidden )
   {   $('#'+shuttle_item+'_MOVE_ALL').addClass('apex_disabled');
   }
    else
   {   $('#'+shuttle_item+'_MOVE_ALL').removeClass('apex_disabled');
   }
        
},

    // function that gets called from plugin
    doIt: function() {
        // plugin attributes
        var daThis = this;
        var shuttle_item = daThis.affectedElements[0].id;
        var search_item  = daThis.action.attribute01;
        // Logging
        var vLogging = true;
        if (vLogging) {
            console.log('Restrict Shuttle Values: search_item=' , search_item);
            console.log('Restrict Shuttle Values: shuttle_item=', shuttle_item);
        }
        apex_restrict_shuttle_values.restrict_values(search_item,shuttle_item);
    }
};
