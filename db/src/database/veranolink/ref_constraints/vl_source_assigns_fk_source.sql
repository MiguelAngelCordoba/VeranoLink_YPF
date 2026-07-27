alter table veranolink.vl_source_assigns
    add constraint vl_source_assigns_fk_source
        foreign key ( id_vl_source_environment )
            references veranolink.vl_sources ( id_vl_source )
        enable;


-- sqlcl_snapshot {"hash":"8cddf4fe041d92ee44519d9a5b40ad616eb151a6","type":"REF_CONSTRAINT","name":"VL_SOURCE_ASSIGNS_FK_SOURCE","schemaName":"VERANOLINK","sxml":""}