alter table veranolink.vl_sources
    add constraint vl_sources_fk_tev
        foreign key ( id_vl_type_environment )
            references veranolink.vl_types_environment ( id_vl_type_environment )
                on delete cascade
        enable;


-- sqlcl_snapshot {"hash":"fc3aee083dd45554e6874af499c3598b4ed9f102","type":"REF_CONSTRAINT","name":"VL_SOURCES_FK_TEV","schemaName":"VERANOLINK","sxml":""}