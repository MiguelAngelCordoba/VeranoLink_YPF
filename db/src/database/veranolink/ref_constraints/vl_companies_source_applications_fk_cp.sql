alter table veranolink.vl_companies_source_applications
    add constraint vl_companies_source_applications_fk_cp
        foreign key ( vl_id_company )
            references veranolink.vl_companies ( vl_id_company )
                on delete cascade
        enable;


-- sqlcl_snapshot {"hash":"9871f43dcfabc186e646199df49eee0c8cd199f3","type":"REF_CONSTRAINT","name":"VL_COMPANIES_SOURCE_APPLICATIONS_FK_CP","schemaName":"VERANOLINK","sxml":""}