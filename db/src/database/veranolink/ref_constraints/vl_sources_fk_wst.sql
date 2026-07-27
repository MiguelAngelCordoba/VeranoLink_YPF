alter table veranolink.vl_sources
    add constraint vl_sources_fk_wst
        foreign key ( id_vl_ws_type )
            references veranolink.vl_ws_types ( id_vl_ws_type )
                on delete cascade
        enable;


-- sqlcl_snapshot {"hash":"11f1390168f7de4060af9cdcfd6db388591347d9","type":"REF_CONSTRAINT","name":"VL_SOURCES_FK_WST","schemaName":"VERANOLINK","sxml":""}