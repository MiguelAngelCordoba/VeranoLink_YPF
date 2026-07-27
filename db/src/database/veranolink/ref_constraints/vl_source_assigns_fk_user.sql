alter table veranolink.vl_source_assigns
    add constraint vl_source_assigns_fk_user
        foreign key ( id_vl_user )
            references veranolink.vl_users ( vl_id_user )
        enable;


-- sqlcl_snapshot {"hash":"541f2ebaee065c1c2e03928b14fced78675e6ec3","type":"REF_CONSTRAINT","name":"VL_SOURCE_ASSIGNS_FK_USER","schemaName":"VERANOLINK","sxml":""}