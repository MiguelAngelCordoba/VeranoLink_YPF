alter table veranolink.vl_path_contexts
    add constraint vl_path_contexts_fk_ct
        foreign key ( id_vl_call_type )
            references veranolink.vl_call_types ( id_vl_call_type )
                on delete cascade
        enable;


-- sqlcl_snapshot {"hash":"e026d6358bc1b4e95b901cac0a51fe05a296812e","type":"REF_CONSTRAINT","name":"VL_PATH_CONTEXTS_FK_CT","schemaName":"VERANOLINK","sxml":""}