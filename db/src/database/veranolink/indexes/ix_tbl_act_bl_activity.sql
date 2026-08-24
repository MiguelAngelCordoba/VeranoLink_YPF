create index veranolink.ix_tbl_act_bl_activity on
    veranolink.tbl_activity_baseline (
        activity_id,
        fecha_carga
    );


-- sqlcl_snapshot {"hash":"7e5e9565ce6459b41420149c00a1c58fcf46aa4b","type":"INDEX","name":"IX_TBL_ACT_BL_ACTIVITY","schemaName":"VERANOLINK","sxml":"\n  <INDEX xmlns=\"http://xmlns.oracle.com/ku\" version=\"1.0\">\n   <SCHEMA>VERANOLINK</SCHEMA>\n   <NAME>IX_TBL_ACT_BL_ACTIVITY</NAME>\n   <TABLE_INDEX>\n      <ON_TABLE>\n         <SCHEMA>VERANOLINK</SCHEMA>\n         <NAME>TBL_ACTIVITY_BASELINE</NAME>\n      </ON_TABLE>\n      <COL_LIST>\n         <COL_LIST_ITEM>\n            <NAME>ACTIVITY_ID</NAME>\n         </COL_LIST_ITEM>\n         <COL_LIST_ITEM>\n            <NAME>FECHA_CARGA</NAME>\n         </COL_LIST_ITEM>\n      </COL_LIST>\n   </TABLE_INDEX>\n</INDEX>"}