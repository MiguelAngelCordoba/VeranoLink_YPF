alter table veranolink.vl_tables_used_on_apus
    add constraint fk_api
        foreign key ( saved_table_id )
            references veranolink.vl_saved_tables ( vl_id_saved_table )
        enable;


-- sqlcl_snapshot {"hash":"60032def1a61c9ad40745e329b06f16171086dbc","type":"REF_CONSTRAINT","name":"FK_API","schemaName":"VERANOLINK","sxml":""}