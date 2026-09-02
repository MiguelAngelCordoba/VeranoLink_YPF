create table veranolink.tbl_project (
    project_id         number not null enable,
    project_code       varchar2(60 byte) not null enable,
    project_name       varchar2(255 byte),
    status             varchar2(20 byte),
    integracion_flag   varchar2(10 byte),
    contract_number    varchar2(50 byte) not null enable,
    fecha_carga        timestamp(6) default systimestamp not null enable,
    estado_integracion varchar2(20 byte) default 'OK' not null enable,
    workspace_code     varchar2(60 byte),
    workspace_id       number
);

alter table veranolink.tbl_project
    add constraint ck_tbl_project_estado
        check ( estado_integracion in ( 'OK', 'DUPLICADO', 'CONTRATO_CAMBIADO' ) ) enable;

alter table veranolink.tbl_project
    add constraint pk_tbl_project primary key ( project_id )
        using index enable;


-- sqlcl_snapshot {"hash":"bcdb120029a5de4597604706488f2d2d913496f1","type":"TABLE","name":"TBL_PROJECT","schemaName":"VERANOLINK","sxml":"\n  <TABLE xmlns=\"http://xmlns.oracle.com/ku\" version=\"1.0\">\n   <SCHEMA>VERANOLINK</SCHEMA>\n   <NAME>TBL_PROJECT</NAME>\n   <RELATIONAL_TABLE>\n      <COL_LIST>\n         <COL_LIST_ITEM>\n            <NAME>PROJECT_ID</NAME>\n            <DATATYPE>NUMBER</DATATYPE>\n            <NOT_NULL></NOT_NULL>\n         </COL_LIST_ITEM>\n         <COL_LIST_ITEM>\n            <NAME>PROJECT_CODE</NAME>\n            <DATATYPE>VARCHAR2</DATATYPE>\n            <LENGTH>60</LENGTH>\n            <COLLATE_NAME>USING_NLS_COMP</COLLATE_NAME>\n            <NOT_NULL></NOT_NULL>\n         </COL_LIST_ITEM>\n         <COL_LIST_ITEM>\n            <NAME>PROJECT_NAME</NAME>\n            <DATATYPE>VARCHAR2</DATATYPE>\n            <LENGTH>255</LENGTH>\n            <COLLATE_NAME>USING_NLS_COMP</COLLATE_NAME>\n         </COL_LIST_ITEM>\n         <COL_LIST_ITEM>\n            <NAME>STATUS</NAME>\n            <DATATYPE>VARCHAR2</DATATYPE>\n            <LENGTH>20</LENGTH>\n            <COLLATE_NAME>USING_NLS_COMP</COLLATE_NAME>\n         </COL_LIST_ITEM>\n         <COL_LIST_ITEM>\n            <NAME>INTEGRACION_FLAG</NAME>\n            <DATATYPE>VARCHAR2</DATATYPE>\n            <LENGTH>10</LENGTH>\n            <COLLATE_NAME>USING_NLS_COMP</COLLATE_NAME>\n         </COL_LIST_ITEM>\n         <COL_LIST_ITEM>\n            <NAME>CONTRACT_NUMBER</NAME>\n            <DATATYPE>VARCHAR2</DATATYPE>\n            <LENGTH>50</LENGTH>\n            <COLLATE_NAME>USING_NLS_COMP</COLLATE_NAME>\n            <NOT_NULL></NOT_NULL>\n         </COL_LIST_ITEM>\n         <COL_LIST_ITEM>\n            <NAME>FECHA_CARGA</NAME>\n            <DATATYPE>TIMESTAMP</DATATYPE>\n            <SCALE>6</SCALE>\n            <DEFAULT>SYSTIMESTAMP</DEFAULT>\n            <NOT_NULL></NOT_NULL>\n         </COL_LIST_ITEM>\n         <COL_LIST_ITEM>\n            <NAME>ESTADO_INTEGRACION</NAME>\n            <DATATYPE>VARCHAR2</DATATYPE>\n            <LENGTH>20</LENGTH>\n            <COLLATE_NAME>USING_NLS_COMP</COLLATE_NAME>\n            <DEFAULT>'OK'</DEFAULT>\n            <NOT_NULL></NOT_NULL>\n         </COL_LIST_ITEM>\n         <COL_LIST_ITEM>\n            <NAME>WORKSPACE_CODE</NAME>\n            <DATATYPE>VARCHAR2</DATATYPE>\n            <LENGTH>60</LENGTH>\n            <COLLATE_NAME>USING_NLS_COMP</COLLATE_NAME>\n         </COL_LIST_ITEM>\n         <COL_LIST_ITEM>\n            <NAME>WORKSPACE_ID</NAME>\n            <DATATYPE>NUMBER</DATATYPE>\n         </COL_LIST_ITEM>\n      </COL_LIST>\n      <CHECK_CONSTRAINT_LIST>\n         <CHECK_CONSTRAINT_LIST_ITEM>\n            <NAME>CK_TBL_PROJECT_ESTADO</NAME>\n            <CONDITION>ESTADO_INTEGRACION IN ('OK', 'DUPLICADO', 'CONTRATO_CAMBIADO')</CONDITION>\n         </CHECK_CONSTRAINT_LIST_ITEM>\n      </CHECK_CONSTRAINT_LIST>\n      <PRIMARY_KEY_CONSTRAINT_LIST>\n         <PRIMARY_KEY_CONSTRAINT_LIST_ITEM>\n            <NAME>PK_TBL_PROJECT</NAME>\n            <COL_LIST>\n               <COL_LIST_ITEM>\n                  <NAME>PROJECT_ID</NAME>\n               </COL_LIST_ITEM>\n            </COL_LIST>\n            <USING_INDEX></USING_INDEX>\n         </PRIMARY_KEY_CONSTRAINT_LIST_ITEM>\n      </PRIMARY_KEY_CONSTRAINT_LIST>\n      <DEFAULT_COLLATION>USING_NLS_COMP</DEFAULT_COLLATION>\n      <PHYSICAL_PROPERTIES>\n         <HEAP_TABLE></HEAP_TABLE>\n      </PHYSICAL_PROPERTIES>\n   </RELATIONAL_TABLE>\n</TABLE>"}