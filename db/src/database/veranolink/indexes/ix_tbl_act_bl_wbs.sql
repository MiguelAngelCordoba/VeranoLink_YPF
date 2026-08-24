create index veranolink.ix_tbl_act_bl_wbs on
    veranolink.tbl_activity_baseline (
        wbs_id
    );


-- sqlcl_snapshot {"hash":"ae000727ca4a96bdc817c5cfb7a44ef659ec8a7f","type":"INDEX","name":"IX_TBL_ACT_BL_WBS","schemaName":"VERANOLINK","sxml":"\n  <INDEX xmlns=\"http://xmlns.oracle.com/ku\" version=\"1.0\">\n   <SCHEMA>VERANOLINK</SCHEMA>\n   <NAME>IX_TBL_ACT_BL_WBS</NAME>\n   <TABLE_INDEX>\n      <ON_TABLE>\n         <SCHEMA>VERANOLINK</SCHEMA>\n         <NAME>TBL_ACTIVITY_BASELINE</NAME>\n      </ON_TABLE>\n      <COL_LIST>\n         <COL_LIST_ITEM>\n            <NAME>WBS_ID</NAME>\n         </COL_LIST_ITEM>\n      </COL_LIST>\n   </TABLE_INDEX>\n</INDEX>"}