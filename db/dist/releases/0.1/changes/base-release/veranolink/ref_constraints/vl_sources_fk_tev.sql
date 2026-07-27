-- liquibase formatted sql
-- changeset VERANOLINK:1785188155747 stripComments:false  logicalFilePath:base-release\veranolink\ref_constraints\vl_sources_fk_tev.sql
-- sqlcl_snapshot db/src/database/veranolink/ref_constraints/vl_sources_fk_tev.sql:null:fc3aee083dd45554e6874af499c3598b4ed9f102:create

alter table veranolink.vl_sources
    add constraint vl_sources_fk_tev
        foreign key ( id_vl_type_environment )
            references veranolink.vl_types_environment ( id_vl_type_environment )
                on delete cascade
        enable;

