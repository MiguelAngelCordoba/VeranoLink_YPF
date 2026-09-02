create index veranolink.idx_log_seq_lote on
    veranolink.log_opc_sequence (
        id_lote
    );


-- sqlcl_snapshot {"hash":"f188fa6cef961bf8909c00bdec7b661d7f7f334d","type":"INDEX","name":"IDX_LOG_SEQ_LOTE","schemaName":"VERANOLINK","sxml":"\n  <INDEX xmlns=\"http://xmlns.oracle.com/ku\" version=\"1.0\">\n   <SCHEMA>VERANOLINK</SCHEMA>\n   <NAME>IDX_LOG_SEQ_LOTE</NAME>\n   <TABLE_INDEX>\n      <ON_TABLE>\n         <SCHEMA>VERANOLINK</SCHEMA>\n         <NAME>LOG_OPC_SEQUENCE</NAME>\n      </ON_TABLE>\n      <COL_LIST>\n         <COL_LIST_ITEM>\n            <NAME>ID_LOTE</NAME>\n         </COL_LIST_ITEM>\n      </COL_LIST>\n   </TABLE_INDEX>\n</INDEX>"}