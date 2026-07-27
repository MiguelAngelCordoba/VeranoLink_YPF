-- liquibase formatted sql
-- changeset VERANOLINK:1785188155765 stripComments:false  logicalFilePath:base-release\veranolink\ref_constraints\vl_source_collections_fk_sa.sql
-- sqlcl_snapshot db/src/database/veranolink/ref_constraints/vl_source_collections_fk_sa.sql:null:21ecae6dd4f95774efbbfe6332d83d5179e38815:create

alter table veranolink.vl_source_collections
    add constraint vl_source_collections_fk_sa
        foreign key ( id_vl_source_application )
            references veranolink.vl_source_applications ( id_vl_source_application )
                on delete cascade
        enable;

