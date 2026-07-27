alter table veranolink.vl_source_collections
    add constraint vl_source_collections_fk_sa
        foreign key ( id_vl_source_application )
            references veranolink.vl_source_applications ( id_vl_source_application )
                on delete cascade
        enable;


-- sqlcl_snapshot {"hash":"21ecae6dd4f95774efbbfe6332d83d5179e38815","type":"REF_CONSTRAINT","name":"VL_SOURCE_COLLECTIONS_FK_SA","schemaName":"VERANOLINK","sxml":""}