create index veranolink.idx_tbl_activity_project on
    veranolink.tbl_activity (
        project_id
    );


-- sqlcl_snapshot {"hash":"3016f657dd1b4b9eb93558c1333461435af035be","type":"INDEX","name":"IDX_TBL_ACTIVITY_PROJECT","schemaName":"VERANOLINK","sxml":"\n  <INDEX xmlns=\"http://xmlns.oracle.com/ku\" version=\"1.0\">\n   <SCHEMA>VERANOLINK</SCHEMA>\n   <NAME>IDX_TBL_ACTIVITY_PROJECT</NAME>\n   <TABLE_INDEX>\n      <ON_TABLE>\n         <SCHEMA>VERANOLINK</SCHEMA>\n         <NAME>TBL_ACTIVITY</NAME>\n      </ON_TABLE>\n      <COL_LIST>\n         <COL_LIST_ITEM>\n            <NAME>PROJECT_ID</NAME>\n         </COL_LIST_ITEM>\n      </COL_LIST>\n   </TABLE_INDEX>\n</INDEX>"}