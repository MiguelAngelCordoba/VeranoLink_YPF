create index veranolink.ix_tbl_prj_bl_vigente on
    veranolink.tbl_project_baseline (
        vigente,
        project_id
    );


-- sqlcl_snapshot {"hash":"22375e5fa10688bee05a4b11bdb75ea55cbcd9af","type":"INDEX","name":"IX_TBL_PRJ_BL_VIGENTE","schemaName":"VERANOLINK","sxml":"\n  <INDEX xmlns=\"http://xmlns.oracle.com/ku\" version=\"1.0\">\n   <SCHEMA>VERANOLINK</SCHEMA>\n   <NAME>IX_TBL_PRJ_BL_VIGENTE</NAME>\n   <TABLE_INDEX>\n      <ON_TABLE>\n         <SCHEMA>VERANOLINK</SCHEMA>\n         <NAME>TBL_PROJECT_BASELINE</NAME>\n      </ON_TABLE>\n      <COL_LIST>\n         <COL_LIST_ITEM>\n            <NAME>VIGENTE</NAME>\n         </COL_LIST_ITEM>\n         <COL_LIST_ITEM>\n            <NAME>PROJECT_ID</NAME>\n         </COL_LIST_ITEM>\n      </COL_LIST>\n   </TABLE_INDEX>\n</INDEX>"}