alter table veranolink.vl_users
    add
        foreign key ( vl_id_company )
            references veranolink.vl_companies ( vl_id_company )
        enable;


-- sqlcl_snapshot {"hash":"6b059d0c9d6e8a04ed7d7331fac96332b5b58776","type":"REF_CONSTRAINT","name":"VL_USERS.VERANOLINK.VL_COMPANIES","schemaName":"VERANOLINK","sxml":""}