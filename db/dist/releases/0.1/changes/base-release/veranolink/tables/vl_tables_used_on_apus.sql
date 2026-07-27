-- liquibase formatted sql
-- changeset VERANOLINK:1785188156190 stripComments:false  logicalFilePath:base-release\veranolink\tables\vl_tables_used_on_apus.sql
-- sqlcl_snapshot db/src/database/veranolink/tables/vl_tables_used_on_apus.sql:null:86a459656abbc167f1fee464fec47c925cf5fa96:create

create table veranolink.vl_tables_used_on_apus (
    apu_id         number not null enable,
    saved_table_id number not null enable
);

alter table veranolink.vl_tables_used_on_apus
    add constraint pk_vl_tables_used primary key ( saved_table_id,
                                                   apu_id )
        using index enable;

