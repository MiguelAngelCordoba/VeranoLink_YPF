alter table veranolink.vl_companies_source_applications
    add constraint vl_companies_source_applications_fk
        foreign key ( id_vl_source_application )
            references veranolink.vl_source_applications ( id_vl_source_application )
                on delete cascade
        enable;


-- sqlcl_snapshot {"hash":"b93ce7fa9370bb35a1550f950dba0c05877e3b40","type":"REF_CONSTRAINT","name":"VL_COMPANIES_SOURCE_APPLICATIONS_FK","schemaName":"VERANOLINK","sxml":""}