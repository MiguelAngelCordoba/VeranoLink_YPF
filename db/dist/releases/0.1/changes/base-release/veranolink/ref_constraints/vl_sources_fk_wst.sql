-- liquibase formatted sql
-- changeset VERANOLINK:1785188155844 stripComments:false  logicalFilePath:base-release\veranolink\ref_constraints\vl_sources_fk_wst.sql
-- sqlcl_snapshot db/src/database/veranolink/ref_constraints/vl_sources_fk_wst.sql:null:11f1390168f7de4060af9cdcfd6db388591347d9:create

alter table veranolink.vl_sources
    add constraint vl_sources_fk_wst
        foreign key ( id_vl_ws_type )
            references veranolink.vl_ws_types ( id_vl_ws_type )
                on delete cascade
        enable;

