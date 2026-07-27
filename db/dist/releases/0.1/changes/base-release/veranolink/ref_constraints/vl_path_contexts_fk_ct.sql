-- liquibase formatted sql
-- changeset VERANOLINK:1785188155692 stripComments:false  logicalFilePath:base-release\veranolink\ref_constraints\vl_path_contexts_fk_ct.sql
-- sqlcl_snapshot db/src/database/veranolink/ref_constraints/vl_path_contexts_fk_ct.sql:null:e026d6358bc1b4e95b901cac0a51fe05a296812e:create

alter table veranolink.vl_path_contexts
    add constraint vl_path_contexts_fk_ct
        foreign key ( id_vl_call_type )
            references veranolink.vl_call_types ( id_vl_call_type )
                on delete cascade
        enable;

