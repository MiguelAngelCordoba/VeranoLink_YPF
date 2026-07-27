-- liquibase formatted sql
-- changeset VERANOLINK:1785188155867 stripComments:false  logicalFilePath:base-release\veranolink\tables\vl_companies_source_applications.sql
-- sqlcl_snapshot db/src/database/veranolink/tables/vl_companies_source_applications.sql:null:a81a951a4064c2c09b49360a12a27947ac222d4d:create

create table veranolink.vl_companies_source_applications (
    vl_id_company             number not null enable,
    id_vl_source_application  number,
    created_date              timestamp(6) default systimestamp,
    id_vl_company_application number generated always as identity minvalue 1 maxvalue 9999999999999999999999999999 increment by 1 cache
    20 noorder nocycle nokeep noscale not null enable,
    vl_state                  number default 1
);

alter table veranolink.vl_companies_source_applications
    add constraint vl_companies_source_applications_pk primary key ( id_vl_company_application )
        using index enable;

alter table veranolink.vl_companies_source_applications
    add constraint vl_companies_source_applications_uk unique ( vl_id_company,
                                                                id_vl_source_application )
        using index enable;

