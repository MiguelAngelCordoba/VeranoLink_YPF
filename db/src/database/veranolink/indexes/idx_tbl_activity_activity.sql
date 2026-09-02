create index veranolink.idx_tbl_activity_activity on
    veranolink.tbl_activity (
        activity_id
    );


-- sqlcl_snapshot {"hash":"b6d73bb11388251e55e3e523e1faca29d5d614a1","type":"INDEX","name":"IDX_TBL_ACTIVITY_ACTIVITY","schemaName":"VERANOLINK","sxml":"\n  <INDEX xmlns=\"http://xmlns.oracle.com/ku\" version=\"1.0\">\n   <SCHEMA>VERANOLINK</SCHEMA>\n   <NAME>IDX_TBL_ACTIVITY_ACTIVITY</NAME>\n   <TABLE_INDEX>\n      <ON_TABLE>\n         <SCHEMA>VERANOLINK</SCHEMA>\n         <NAME>TBL_ACTIVITY</NAME>\n      </ON_TABLE>\n      <COL_LIST>\n         <COL_LIST_ITEM>\n            <NAME>ACTIVITY_ID</NAME>\n         </COL_LIST_ITEM>\n      </COL_LIST>\n   </TABLE_INDEX>\n</INDEX>"}