create index veranolink.idx_log_project on
    veranolink.log_opc_sequence (
        project_id,
        resultado
    );


-- sqlcl_snapshot {"hash":"be9856583c1f61006abb2a5e161df195f5b3cec0","type":"INDEX","name":"IDX_LOG_PROJECT","schemaName":"VERANOLINK","sxml":"\n  <INDEX xmlns=\"http://xmlns.oracle.com/ku\" version=\"1.0\">\n   <SCHEMA>VERANOLINK</SCHEMA>\n   <NAME>IDX_LOG_PROJECT</NAME>\n   <TABLE_INDEX>\n      <ON_TABLE>\n         <SCHEMA>VERANOLINK</SCHEMA>\n         <NAME>LOG_OPC_SEQUENCE</NAME>\n      </ON_TABLE>\n      <COL_LIST>\n         <COL_LIST_ITEM>\n            <NAME>PROJECT_ID</NAME>\n         </COL_LIST_ITEM>\n         <COL_LIST_ITEM>\n            <NAME>RESULTADO</NAME>\n         </COL_LIST_ITEM>\n      </COL_LIST>\n   </TABLE_INDEX>\n</INDEX>"}