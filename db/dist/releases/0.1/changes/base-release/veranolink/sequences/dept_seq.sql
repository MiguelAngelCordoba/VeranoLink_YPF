-- liquibase formatted sql
-- changeset VERANOLINK:1785188155811 stripComments:false  logicalFilePath:base-release\veranolink\sequences\dept_seq.sql
-- sqlcl_snapshot db/src/database/veranolink/sequences/dept_seq.sql:null:7f1e7147db71c6183a708af0b137bace0be636ee:create

create sequence veranolink.dept_seq minvalue 1 maxvalue 9999999999999999999999999999 increment by 1 /* start with n */ cache 20 noorder
nocycle nokeep noscale global;

