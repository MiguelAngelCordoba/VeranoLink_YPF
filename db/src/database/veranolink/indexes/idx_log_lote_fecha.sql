create index veranolink.idx_log_lote_fecha on
    veranolink.log_lote (
        fecha_ejecucion
    desc );


-- sqlcl_snapshot {"hash":"50391a1c6c3f6996551477479c8a2e3b7f4fea97","type":"INDEX","name":"IDX_LOG_LOTE_FECHA","schemaName":"VERANOLINK","sxml":"\n  <INDEX xmlns=\"http://xmlns.oracle.com/ku\" version=\"1.0\">\n   <SCHEMA>VERANOLINK</SCHEMA>\n   <NAME>IDX_LOG_LOTE_FECHA</NAME>\n   <TABLE_INDEX>\n      <ON_TABLE>\n         <SCHEMA>VERANOLINK</SCHEMA>\n         <NAME>LOG_LOTE</NAME>\n      </ON_TABLE>\n      <COL_LIST>\n         <COL_LIST_ITEM>\n            <NAME>\"FECHA_EJECUCION\"</NAME>\n            <DESC></DESC>\n         </COL_LIST_ITEM>\n      </COL_LIST>\n   </TABLE_INDEX>\n</INDEX>"}