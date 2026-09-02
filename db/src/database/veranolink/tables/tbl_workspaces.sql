create table veranolink.tbl_workspaces (
    workspace_id         number not null enable,
    workspace_code       varchar2(60 byte) not null enable,
    workspace_name       varchar2(255 byte),
    is_production        varchar2(1 byte) not null enable,
    fecha_sincronizacion timestamp(6) not null enable
);

alter table veranolink.tbl_workspaces
    add constraint ck_tbl_ws_is_production
        check ( is_production in ( 'Y', 'N' ) ) enable;

alter table veranolink.tbl_workspaces
    add constraint pk_tbl_workspaces primary key ( workspace_id )
        using index enable;

alter table veranolink.tbl_workspaces add constraint uk_tbl_workspaces_code unique ( workspace_code )
    using index enable;


-- sqlcl_snapshot {"hash":"df47d77035b4bf3d0040d7a95dc39951805d5d2b","type":"TABLE","name":"TBL_WORKSPACES","schemaName":"VERANOLINK","sxml":"\n  <TABLE xmlns=\"http://xmlns.oracle.com/ku\" version=\"1.0\">\n   <SCHEMA>VERANOLINK</SCHEMA>\n   <NAME>TBL_WORKSPACES</NAME>\n   <RELATIONAL_TABLE>\n      <COL_LIST>\n         <COL_LIST_ITEM>\n            <NAME>WORKSPACE_ID</NAME>\n            <DATATYPE>NUMBER</DATATYPE>\n            <NOT_NULL></NOT_NULL>\n         </COL_LIST_ITEM>\n         <COL_LIST_ITEM>\n            <NAME>WORKSPACE_CODE</NAME>\n            <DATATYPE>VARCHAR2</DATATYPE>\n            <LENGTH>60</LENGTH>\n            <COLLATE_NAME>USING_NLS_COMP</COLLATE_NAME>\n            <NOT_NULL></NOT_NULL>\n         </COL_LIST_ITEM>\n         <COL_LIST_ITEM>\n            <NAME>WORKSPACE_NAME</NAME>\n            <DATATYPE>VARCHAR2</DATATYPE>\n            <LENGTH>255</LENGTH>\n            <COLLATE_NAME>USING_NLS_COMP</COLLATE_NAME>\n         </COL_LIST_ITEM>\n         <COL_LIST_ITEM>\n            <NAME>IS_PRODUCTION</NAME>\n            <DATATYPE>VARCHAR2</DATATYPE>\n            <LENGTH>1</LENGTH>\n            <COLLATE_NAME>USING_NLS_COMP</COLLATE_NAME>\n            <NOT_NULL></NOT_NULL>\n         </COL_LIST_ITEM>\n         <COL_LIST_ITEM>\n            <NAME>FECHA_SINCRONIZACION</NAME>\n            <DATATYPE>TIMESTAMP</DATATYPE>\n            <SCALE>6</SCALE>\n            <NOT_NULL></NOT_NULL>\n         </COL_LIST_ITEM>\n      </COL_LIST>\n      <CHECK_CONSTRAINT_LIST>\n         <CHECK_CONSTRAINT_LIST_ITEM>\n            <NAME>CK_TBL_WS_IS_PRODUCTION</NAME>\n            <CONDITION>IS_PRODUCTION IN ('Y','N')</CONDITION>\n         </CHECK_CONSTRAINT_LIST_ITEM>\n      </CHECK_CONSTRAINT_LIST>\n      <PRIMARY_KEY_CONSTRAINT_LIST>\n         <PRIMARY_KEY_CONSTRAINT_LIST_ITEM>\n            <NAME>PK_TBL_WORKSPACES</NAME>\n            <COL_LIST>\n               <COL_LIST_ITEM>\n                  <NAME>WORKSPACE_ID</NAME>\n               </COL_LIST_ITEM>\n            </COL_LIST>\n            <USING_INDEX></USING_INDEX>\n         </PRIMARY_KEY_CONSTRAINT_LIST_ITEM>\n      </PRIMARY_KEY_CONSTRAINT_LIST>\n      <UNIQUE_KEY_CONSTRAINT_LIST>\n         <UNIQUE_KEY_CONSTRAINT_LIST_ITEM>\n            <NAME>UK_TBL_WORKSPACES_CODE</NAME>\n            <COL_LIST>\n               <COL_LIST_ITEM>\n                  <NAME>WORKSPACE_CODE</NAME>\n               </COL_LIST_ITEM>\n            </COL_LIST>\n            <USING_INDEX></USING_INDEX>\n         </UNIQUE_KEY_CONSTRAINT_LIST_ITEM>\n      </UNIQUE_KEY_CONSTRAINT_LIST>\n      <DEFAULT_COLLATION>USING_NLS_COMP</DEFAULT_COLLATION>\n      <PHYSICAL_PROPERTIES>\n         <HEAP_TABLE></HEAP_TABLE>\n      </PHYSICAL_PROPERTIES>\n   </RELATIONAL_TABLE>\n</TABLE>"}