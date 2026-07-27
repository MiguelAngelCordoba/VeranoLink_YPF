-- liquibase formatted sql
-- changeset VERANOLINK:1785188155787 stripComments:false  logicalFilePath:base-release\veranolink\ref_constraints\vl_source_assigns_fk_source.sql
-- sqlcl_snapshot db/src/database/veranolink/ref_constraints/vl_source_assigns_fk_source.sql:null:8cddf4fe041d92ee44519d9a5b40ad616eb151a6:create

alter table veranolink.vl_source_assigns
    add constraint vl_source_assigns_fk_source
        foreign key ( id_vl_source_environment )
            references veranolink.vl_sources ( id_vl_source )
        enable;

