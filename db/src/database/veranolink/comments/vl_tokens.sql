comment on table veranolink.vl_tokens is
    'Tabla que almacena los respectivos TOKENS';

comment on column veranolink.vl_tokens.access_token is
    'Token de Acceso';

comment on column veranolink.vl_tokens.created_date is
    'Fecha de creaci�n del token';

comment on column veranolink.vl_tokens.expirein is
    'Tiempo en que expira';

comment on column veranolink.vl_tokens.id_vl_source_application is
    'Fuente Asociado del Token';

comment on column veranolink.vl_tokens.id_vl_token is
    'Autoincremental';

comment on column veranolink.vl_tokens.primeidentityapp is
    'Parametro para OPC';

comment on column veranolink.vl_tokens.primetenant is
    'Parametro para OPC';

comment on column veranolink.vl_tokens.primetenantcode is
    'Parametro para OPC';

comment on column veranolink.vl_tokens.token_type is
    'Tipo de Token';

comment on column veranolink.vl_tokens.userid is
    'Parametro para OPC';

comment on column veranolink.vl_tokens.x_prime_identity_app is
    'Parametro para OPC';

comment on column veranolink.vl_tokens.x_prime_region is
    'Parametro para OPC';

comment on column veranolink.vl_tokens.x_prime_tenant is
    'Parametro para OPC';


-- sqlcl_snapshot {"hash":"083c716c8e73e09c2200c04a9a8ed11b98d03c92","type":"COMMENT","name":"vl_tokens","schemaName":"veranolink","sxml":""}