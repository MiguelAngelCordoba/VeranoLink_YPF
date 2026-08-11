create index veranolink.ix_tbl_wbs_wbsid_upd on
    veranolink.tbl_wbs (
        wbs_id,
        updatedate
    );


-- sqlcl_snapshot {"hash":"a93dfd7edceebe56abbc72912ccebfce961f6972","type":"INDEX","name":"IX_TBL_WBS_WBSID_UPD","schemaName":"VERANOLINK","sxml":"\n  <INDEX xmlns=\"http://xmlns.oracle.com/ku\" version=\"1.0\">\n   <SCHEMA>VERANOLINK</SCHEMA>\n   <NAME>IX_TBL_WBS_WBSID_UPD</NAME>\n   <TABLE_INDEX>\n      <ON_TABLE>\n         <SCHEMA>VERANOLINK</SCHEMA>\n         <NAME>TBL_WBS</NAME>\n      </ON_TABLE>\n      <COL_LIST>\n         <COL_LIST_ITEM>\n            <NAME>WBS_ID</NAME>\n         </COL_LIST_ITEM>\n         <COL_LIST_ITEM>\n            <NAME>UPDATEDATE</NAME>\n         </COL_LIST_ITEM>\n      </COL_LIST>\n   </TABLE_INDEX>\n</INDEX>"}