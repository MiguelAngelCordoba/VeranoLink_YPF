create index veranolink.ix_tbl_wbs_project_upd on
    veranolink.tbl_wbs (
        project_id,
        updatedate
    );


-- sqlcl_snapshot {"hash":"b81f701f29b9d09a716e9936090d3500dd7c05bd","type":"INDEX","name":"IX_TBL_WBS_PROJECT_UPD","schemaName":"VERANOLINK","sxml":"\n  <INDEX xmlns=\"http://xmlns.oracle.com/ku\" version=\"1.0\">\n   <SCHEMA>VERANOLINK</SCHEMA>\n   <NAME>IX_TBL_WBS_PROJECT_UPD</NAME>\n   <TABLE_INDEX>\n      <ON_TABLE>\n         <SCHEMA>VERANOLINK</SCHEMA>\n         <NAME>TBL_WBS</NAME>\n      </ON_TABLE>\n      <COL_LIST>\n         <COL_LIST_ITEM>\n            <NAME>PROJECT_ID</NAME>\n         </COL_LIST_ITEM>\n         <COL_LIST_ITEM>\n            <NAME>UPDATEDATE</NAME>\n         </COL_LIST_ITEM>\n      </COL_LIST>\n   </TABLE_INDEX>\n</INDEX>"}