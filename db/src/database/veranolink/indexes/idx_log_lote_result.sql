create index veranolink.idx_log_lote_result on
    veranolink.log_lote (
        resultado,
        fecha_ejecucion
    desc );


-- sqlcl_snapshot {"hash":"d9b966326e55ae3db275332b33e4fc7dcf12f905","type":"INDEX","name":"IDX_LOG_LOTE_RESULT","schemaName":"VERANOLINK","sxml":"\n  <INDEX xmlns=\"http://xmlns.oracle.com/ku\" version=\"1.0\">\n   <SCHEMA>VERANOLINK</SCHEMA>\n   <NAME>IDX_LOG_LOTE_RESULT</NAME>\n   <TABLE_INDEX>\n      <ON_TABLE>\n         <SCHEMA>VERANOLINK</SCHEMA>\n         <NAME>LOG_LOTE</NAME>\n      </ON_TABLE>\n      <COL_LIST>\n         <COL_LIST_ITEM>\n            <NAME>RESULTADO</NAME>\n         </COL_LIST_ITEM>\n         <COL_LIST_ITEM>\n            <NAME>\"FECHA_EJECUCION\"</NAME>\n            <DESC></DESC>\n         </COL_LIST_ITEM>\n      </COL_LIST>\n   </TABLE_INDEX>\n</INDEX>"}