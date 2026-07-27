alter table veranolink.vl_tables_used_on_apus
    add constraint fk_user
        foreign key ( apu_id )
            references veranolink.vl_apu_tables ( id_vl_apu_table )
        enable;


-- sqlcl_snapshot {"hash":"72ad65aa9d12b36b89820bbd21a6e27b9610cd4c","type":"REF_CONSTRAINT","name":"FK_USER","schemaName":"VERANOLINK","sxml":""}