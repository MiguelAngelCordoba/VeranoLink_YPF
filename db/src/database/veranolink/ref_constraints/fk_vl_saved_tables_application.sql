alter table veranolink.vl_saved_tables
    add constraint fk_vl_saved_tables_application
        foreign key ( application )
            references veranolink.vl_source_applications ( id_vl_source_application )
        enable;


-- sqlcl_snapshot {"hash":"c383cd9b52fb82e3021c9f1b86333b0d082651b1","type":"REF_CONSTRAINT","name":"FK_VL_SAVED_TABLES_APPLICATION","schemaName":"VERANOLINK","sxml":""}