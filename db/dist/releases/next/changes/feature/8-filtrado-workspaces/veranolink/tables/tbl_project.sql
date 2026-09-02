-- liquibase formatted sql
-- changeset VERANOLINK:1788367209998 stripComments:false  logicalFilePath:feature\8-filtrado-workspaces\veranolink\tables\tbl_project.sql
-- sqlcl_snapshot db/src/database/veranolink/tables/tbl_project.sql:c55a8277a649e95527bf19103635cc718859ae37:a55ef6060391c21ed91a3eaf7c8fd528aa71c5e9:alter

alter table veranolink.tbl_project add (
    workspace_id number
)
/

