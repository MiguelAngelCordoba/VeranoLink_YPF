-- liquibase formatted sql
-- changeset VERANOLINK:1785188155803 stripComments:false  logicalFilePath:base-release\veranolink\sequences\emp_seq.sql
-- sqlcl_snapshot db/src/database/veranolink/sequences/emp_seq.sql:null:2ddcf81e6730d8b2f3ba525fe65bc7022d603cfb:create

create sequence veranolink.emp_seq minvalue 1 maxvalue 9999999999999999999999999999 increment by 1 /* start with n */ cache 20 noorder
nocycle nokeep noscale global;

