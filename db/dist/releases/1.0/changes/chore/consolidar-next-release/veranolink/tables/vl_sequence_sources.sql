-- liquibase formatted sql
-- changeset VERANOLINK:1788372755509 stripComments:false  logicalFilePath:chore\consolidar-next-release\veranolink\tables\vl_sequence_sources.sql
-- sqlcl_snapshot db/src/database/veranolink/tables/vl_sequence_sources.sql:null:b6afa8a044ca8863bb7b8ddc29a281fbaaadb9d4:create

create table veranolink.vl_sequence_sources (
    id_vl_sequence_source number generated always as identity minvalue 1 maxvalue 9999999999999999999999999999 increment by 1 cache 20
    noorder nocycle nokeep noscale not null enable,
    company               varchar2(50 byte) not null enable,
    environment           number not null enable,
    source_url            varchar2(1000 byte) not null enable,
    source_authentication varchar2(1000 byte) not null enable,
    created_date          timestamp(6) default systimestamp
);

alter table veranolink.vl_sequence_sources
    add constraint uk_vl_seq_company_env unique ( company,
                                                  environment )
        using index enable;

alter table veranolink.vl_sequence_sources add primary key ( id_vl_sequence_source )
    using index enable;

