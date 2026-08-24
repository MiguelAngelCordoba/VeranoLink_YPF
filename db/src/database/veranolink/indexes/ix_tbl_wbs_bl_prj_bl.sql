create index veranolink.ix_tbl_wbs_bl_prj_bl on
    veranolink.tbl_wbs_baseline (
        project_id,
        project_baseline_id
    );


-- sqlcl_snapshot {"hash":"026816207a6864d8464742e7563ef06833989a61","type":"INDEX","name":"IX_TBL_WBS_BL_PRJ_BL","schemaName":"VERANOLINK","sxml":"\n  <INDEX xmlns=\"http://xmlns.oracle.com/ku\" version=\"1.0\">\n   <SCHEMA>VERANOLINK</SCHEMA>\n   <NAME>IX_TBL_WBS_BL_PRJ_BL</NAME>\n   <TABLE_INDEX>\n      <ON_TABLE>\n         <SCHEMA>VERANOLINK</SCHEMA>\n         <NAME>TBL_WBS_BASELINE</NAME>\n      </ON_TABLE>\n      <COL_LIST>\n         <COL_LIST_ITEM>\n            <NAME>PROJECT_ID</NAME>\n         </COL_LIST_ITEM>\n         <COL_LIST_ITEM>\n            <NAME>PROJECT_BASELINE_ID</NAME>\n         </COL_LIST_ITEM>\n      </COL_LIST>\n   </TABLE_INDEX>\n</INDEX>"}