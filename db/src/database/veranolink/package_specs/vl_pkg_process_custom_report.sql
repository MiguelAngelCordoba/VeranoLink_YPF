create or replace package veranolink.vl_pkg_process_custom_report as
    procedure collect_column_info (
        p_query          in clob,
        p_collection     in varchar2,
        p_detailed_stats in varchar2 default 'N',
        p_company_name   in varchar2
    );

    procedure create_group_and_user (
        company_name  in varchar2,
        user_api      in varchar2,
        user_api_pass in varchar2
    );

    procedure update_user_pass (
        user_api      in varchar2,
        user_old_pass in varchar2,
        user_new_pass in varchar2
    );

    procedure run_create_user (
        company_name  in varchar2,
        user_api      in varchar2,
        user_api_pass in varchar2
    );

    procedure run_update_user_pass (
        user_api      in varchar2,
        user_old_pass in varchar2,
        user_new_pass in varchar2
    );

    procedure create_template_handler (
        company_name    in varchar2,
        name_template   in varchar2,
        api_query       in varchar2,
        api_description in varchar2,
        user_id         in number
    );

    procedure update_template_handler (
        company_name  in varchar2,
        name_template in varchar2,
        api_query     in varchar2,
        id_apu_tablea in number
    );

    procedure update_pw_user (
        user_old_pass in varchar2,
        user_new_pass in varchar2
    );

    procedure run_update_pw_user (
        user_old_pass in varchar2,
        user_new_pass in varchar2
    );

end vl_pkg_process_custom_report;
/


-- sqlcl_snapshot {"hash":"40930ee011e05b3ca9c9486c7588a60b67f57cea","type":"PACKAGE_SPEC","name":"VL_PKG_PROCESS_CUSTOM_REPORT","schemaName":"VERANOLINK","sxml":""}