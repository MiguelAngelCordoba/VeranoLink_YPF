alter table veranolink.vl_companies
    add
        foreign key ( vl_id_country )
            references veranolink.vl_countries ( vl_id_country )
        enable;


-- sqlcl_snapshot {"hash":"6d01817f5d75d0edd4b11ef3d1e05e525478e7e7","type":"REF_CONSTRAINT","name":"VL_COMPANIES.VERANOLINK.VL_COUNTRIES","schemaName":"VERANOLINK","sxml":""}