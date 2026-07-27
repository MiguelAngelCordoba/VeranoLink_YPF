alter table veranolink.vl_sources
    add constraint vl_sources_fk_ca
        foreign key ( id_vl_company_application )
            references veranolink.vl_companies_source_applications ( id_vl_company_application )
        enable;


-- sqlcl_snapshot {"hash":"cf1add700c76365165e00b8c8086f7f202fbd82f","type":"REF_CONSTRAINT","name":"VL_SOURCES_FK_CA","schemaName":"VERANOLINK","sxml":""}