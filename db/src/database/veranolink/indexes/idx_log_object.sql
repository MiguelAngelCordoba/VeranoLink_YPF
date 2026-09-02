create index veranolink.idx_log_object on
    veranolink.log_opc_sequence (
        tipo_objeto,
        object_id,
        resultado
    );


-- sqlcl_snapshot {"hash":"ecb197550979abe65fa0a10f27d274ad1009fa08","type":"INDEX","name":"IDX_LOG_OBJECT","schemaName":"VERANOLINK","sxml":"\n  <INDEX xmlns=\"http://xmlns.oracle.com/ku\" version=\"1.0\">\n   <SCHEMA>VERANOLINK</SCHEMA>\n   <NAME>IDX_LOG_OBJECT</NAME>\n   <TABLE_INDEX>\n      <ON_TABLE>\n         <SCHEMA>VERANOLINK</SCHEMA>\n         <NAME>LOG_OPC_SEQUENCE</NAME>\n      </ON_TABLE>\n      <COL_LIST>\n         <COL_LIST_ITEM>\n            <NAME>TIPO_OBJETO</NAME>\n         </COL_LIST_ITEM>\n         <COL_LIST_ITEM>\n            <NAME>OBJECT_ID</NAME>\n         </COL_LIST_ITEM>\n         <COL_LIST_ITEM>\n            <NAME>RESULTADO</NAME>\n         </COL_LIST_ITEM>\n      </COL_LIST>\n   </TABLE_INDEX>\n</INDEX>"}