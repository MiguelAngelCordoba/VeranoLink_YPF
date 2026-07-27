-- liquibase formatted sql
-- changeset veranolink:1785188144746 stripComments:false  logicalFilePath:base-release\veranolink\comments\vl_users.sql
-- sqlcl_snapshot db/src/database/veranolink/comments/vl_users.sql:null:504930d1ae1ef012a3d2d917f0f5ddf2e2b590ea:create

comment on column veranolink.vl_users.active is
    'Activacion de usuario cuando el token y recuperacion sea exitoso.';

comment on column veranolink.vl_users.created_date is
    'Campo de fecha de creaci�n.';

comment on column veranolink.vl_users.email is
    'Correo electr�nico por usuario, identificador principal del usuario.';

comment on column veranolink.vl_users.name is
    'Nombre por usuario, puede ser nombre parcial o completo.';

comment on column veranolink.vl_users.password is
    'Contrase�a encriptada por SHA256.';

comment on column veranolink.vl_users.state is
    'Campo para asignar un estado al usuario (1= Activo, 2= Inactivo).';

comment on column veranolink.vl_users.time_expired is
    'Tiempo de exipraci�n del token / solicitud de recuperaci�n de contrase�a.';

comment on column veranolink.vl_users.token is
    'Campo para token para cuando el usuario solicite recuperar la contrase�a.';

comment on column veranolink.vl_users.vl_id_company is
    'Llave for�nea de la tabla VL_COMPANIES, asigna una compa�ia a cada usuario.';

comment on column veranolink.vl_users.vl_id_rol is
    'Llave for�nea de la tabla VL_ROLES, asigna un rol a cada usuario (Admin, SA, User).';

comment on column veranolink.vl_users.vl_id_user is
    'ID cons ecuencia autoincremental.';

