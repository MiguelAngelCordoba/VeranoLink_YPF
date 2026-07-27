alter table veranolink.vl_users
    add
        foreign key ( vl_id_rol )
            references veranolink.vl_roles ( vl_id_rol )
        enable;


-- sqlcl_snapshot {"hash":"3b5994d46d78b6b277fe1e4197f650f2a94ce16a","type":"REF_CONSTRAINT","name":"VL_USERS.VERANOLINK.VL_ROLES","schemaName":"VERANOLINK","sxml":""}