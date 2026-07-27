
--
        
DECLARE

  l_roles     OWA.VC_ARR;
  l_modules   OWA.VC_ARR;
  l_patterns  OWA.VC_ARR;

BEGIN
  ORDS.ENABLE_SCHEMA(
      p_enabled             => TRUE,
      p_url_mapping_type    => 'BASE_PATH',
      p_url_mapping_pattern => 'api',
      p_auto_rest_auth      => TRUE);

  ORDS.DEFINE_MODULE(
      p_module_name    => 'oracle.example.hr',
      p_base_path      => '/hr/',
      p_items_per_page => 25,
      p_status         => 'PUBLISHED',
      p_comments       => NULL);

  ORDS.DEFINE_TEMPLATE(
      p_module_name    => 'oracle.example.hr',
      p_pattern        => 'empsec/:empname',
      p_priority       => 0,
      p_etag_type      => 'HASH',
      p_etag_query     => NULL,
      p_comments       => NULL);

  ORDS.DEFINE_HANDLER(
      p_module_name    => 'oracle.example.hr',
      p_pattern        => 'empsec/:empname',
      p_method         => 'GET',
      p_source_type    => 'json/collection',
      p_items_per_page => 25,
      p_mimes_allowed  => NULL,
      p_comments       => NULL,
      p_source         => 
'select empno, ename, deptno, job from emp 
	where ((select job from emp where ename = :empname) IN (''PRESIDENT'', ''MANAGER'')) 
    OR  
    (deptno = (select deptno from emp where ename = :empname)) 
order by deptno, ename
');

  ORDS.DEFINE_TEMPLATE(
      p_module_name    => 'oracle.example.hr',
      p_pattern        => 'empsecformat/:empname',
      p_priority       => 0,
      p_etag_type      => 'HASH',
      p_etag_query     => NULL,
      p_comments       => NULL);

  ORDS.DEFINE_HANDLER(
      p_module_name    => 'oracle.example.hr',
      p_pattern        => 'empsecformat/:empname',
      p_method         => 'GET',
      p_source_type    => 'plsql/block',
      p_items_per_page => 25,
      p_mimes_allowed  => NULL,
      p_comments       => NULL,
      p_source         => 
'DECLARE
  prevdeptno     number;
  total_rows     number;
  deptloc        varchar2(20);
  deptname       varchar2(20);
  
  CURSOR         getemps is select * from emp 
                             start with ename = :empname
                           connect by prior empno = mgr
                             order siblings by deptno, ename;
BEGIN
  sys.htp.htmlopen;
  sys.htp.headopen;
  sys.htp.title(''Hierarchical Department Report for Employee ''||wwv_flow_escape.html(:empname));
  sys.htp.headclose;
  sys.htp.bodyopen;
 
  for l_employee in getemps 
  loop
      if l_employee.deptno != prevdeptno or prevdeptno is null then
          select dname, loc 
            into deptname, deptloc 
            from dept 
           where deptno = l_employee.deptno;
           
          if prevdeptno is not null then
              sys.htp.print(''</ul>'');
          end if;

          sys.htp.print(''Department '' || wwv_flow_escape.html(deptname) || '' located in '' || wwv_flow_escape.html(deptloc)' || ' || ''<p/>'');
          sys.htp.print(''<ul>'');
      end if;

      sys.htp.print(''<li>'' || wwv_flow_escape.html(l_employee.ename) || '', ''  || wwv_flow_escape.html(l_employee.empno) || '', '' || 
                        wwv_flow_escape.html(l_employee.job) || '', '' || wwv_flow_escape.html(l_employee.sal) || ''</li>'');

      prevdeptno := l_employee.deptno;
      total_rows := getemps%ROWCOUNT;
      
  end loop;

  if total_rows > 0 then
      sys.htp.print(''</ul>'');
  end if;

  sys.htp.bodyclose;
  sys.htp.htmlclose;
END;');

  ORDS.DEFINE_TEMPLATE(
      p_module_name    => 'oracle.example.hr',
      p_pattern        => 'employees/',
      p_priority       => 0,
      p_etag_type      => 'HASH',
      p_etag_query     => NULL,
      p_comments       => NULL);

  ORDS.DEFINE_HANDLER(
      p_module_name    => 'oracle.example.hr',
      p_pattern        => 'employees/',
      p_method         => 'GET',
      p_source_type    => 'json/collection',
      p_items_per_page => 25,
      p_mimes_allowed  => NULL,
      p_comments       => NULL,
      p_source         => 
'select empno "$uri", rn, empno, ename, job, hiredate, mgr, sal, comm, deptno
  from (
       select emp.*
            , row_number() over (order by empno) rn
         from emp
       ) tmp');

  ORDS.DEFINE_TEMPLATE(
      p_module_name    => 'oracle.example.hr',
      p_pattern        => 'version/',
      p_priority       => 0,
      p_etag_type      => 'HASH',
      p_etag_query     => NULL,
      p_comments       => NULL);

  ORDS.DEFINE_HANDLER(
      p_module_name    => 'oracle.example.hr',
      p_pattern        => 'version/',
      p_method         => 'GET',
      p_source_type    => 'plsql/block',
      p_items_per_page => 25,
      p_mimes_allowed  => NULL,
      p_comments       => NULL,
      p_source         => 
'begin 
 sys.htp.p(''{"version": "23.1"}'');
end;');

  ORDS.DEFINE_TEMPLATE(
      p_module_name    => 'oracle.example.hr',
      p_pattern        => 'employees/:id',
      p_priority       => 0,
      p_etag_type      => 'HASH',
      p_etag_query     => NULL,
      p_comments       => NULL);

  ORDS.DEFINE_HANDLER(
      p_module_name    => 'oracle.example.hr',
      p_pattern        => 'employees/:id',
      p_method         => 'GET',
      p_source_type    => 'json/item',
      p_items_per_page => 25,
      p_mimes_allowed  => NULL,
      p_comments       => NULL,
      p_source         => 
'select * from emp
where empno = :id');

  ORDS.DEFINE_HANDLER(
      p_module_name    => 'oracle.example.hr',
      p_pattern        => 'employees/:id',
      p_method         => 'PUT',
      p_source_type    => 'plsql/block',
      p_items_per_page => 25,
      p_mimes_allowed  => NULL,
      p_comments       => NULL,
      p_source         => 
'begin
    update emp set ename = :ename, job = :job, hiredate = :hiredate, mgr = :mgr, sal = :sal, comm = :comm, deptno = :deptno
    where empno = :id;
    :status := 200;
    :location := :id;
exception
    when others then
        :status := 400;
        sys.htp.p( sys.htf.escape_sc(sqlerrm) );
end;');

  ORDS.DEFINE_PARAMETER(
      p_module_name        => 'oracle.example.hr',
      p_pattern            => 'employees/:id',
      p_method             => 'PUT',
      p_name               => 'X-APEX-FORWARD',
      p_bind_variable_name => 'location',
      p_source_type        => 'HEADER',
      p_param_type         => 'STRING',
      p_access_method      => 'OUT',
      p_comments           => NULL);

  ORDS.DEFINE_PARAMETER(
      p_module_name        => 'oracle.example.hr',
      p_pattern            => 'employees/:id',
      p_method             => 'PUT',
      p_name               => 'ID',
      p_bind_variable_name => 'id',
      p_source_type        => 'HEADER',
      p_param_type         => 'STRING',
      p_access_method      => 'IN',
      p_comments           => NULL);

  ORDS.DEFINE_PARAMETER(
      p_module_name        => 'oracle.example.hr',
      p_pattern            => 'employees/:id',
      p_method             => 'PUT',
      p_name               => 'X-APEX-STATUS-CODE',
      p_bind_variable_name => 'status',
      p_source_type        => 'HEADER',
      p_param_type         => 'INT',
      p_access_method      => 'OUT',
      p_comments           => NULL);

  ORDS.DEFINE_TEMPLATE(
      p_module_name    => 'oracle.example.hr',
      p_pattern        => 'empinfo/',
      p_priority       => 0,
      p_etag_type      => 'HASH',
      p_etag_query     => NULL,
      p_comments       => NULL);

  ORDS.DEFINE_HANDLER(
      p_module_name    => 'oracle.example.hr',
      p_pattern        => 'empinfo/',
      p_method         => 'GET',
      p_source_type    => 'json/collection',
      p_items_per_page => 25,
      p_mimes_allowed  => NULL,
      p_comments       => NULL,
      p_source         => 
'select * from emp');

  ORDS.DEFINE_TEMPLATE(
      p_module_name    => 'oracle.example.hr',
      p_pattern        => 'emp_post_example/',
      p_priority       => 0,
      p_etag_type      => 'HASH',
      p_etag_query     => NULL,
      p_comments       => NULL);

  ORDS.DEFINE_HANDLER(
      p_module_name    => 'oracle.example.hr',
      p_pattern        => 'emp_post_example/',
      p_method         => 'POST',
      p_source_type    => 'plsql/block',
      p_mimes_allowed  => NULL,
      p_comments       => NULL,
      p_source         => 
'DECLARE
 new_id integer;
 current_date date;
BEGIN
    select sysdate into current_date from dual;
    insert into emp 
     (empno, ename, job, mgr, hiredate, sal, comm, deptno)
    VALUES
     (null, :ename, :ejob, :mgr, current_date, :sal, :comm, :deptno)
    returning empno into new_id;
    :status_code := 201;
    :forward_location := ''../employees/''||new_id;
exception
  WHEN VALUE_ERROR
        THEN
            :errmsg := ''SALARY must be a number.'';
            :status_code := 400;
 when others then 
	:status_code := 400;
	:errmsg := sqlerrm;
end;');

  ORDS.DEFINE_PARAMETER(
      p_module_name        => 'oracle.example.hr',
      p_pattern            => 'emp_post_example/',
      p_method             => 'POST',
      p_name               => 'ErrorMessage',
      p_bind_variable_name => 'errmsg',
      p_source_type        => 'RESPONSE',
      p_param_type         => 'STRING',
      p_access_method      => 'OUT',
      p_comments           => NULL);

  ORDS.DEFINE_PARAMETER(
      p_module_name        => 'oracle.example.hr',
      p_pattern            => 'emp_post_example/',
      p_method             => 'POST',
      p_name               => 'EmpName',
      p_bind_variable_name => 'ename',
      p_source_type        => 'HEADER',
      p_param_type         => 'STRING',
      p_access_method      => 'IN',
      p_comments           => NULL);

  ORDS.DEFINE_PARAMETER(
      p_module_name        => 'oracle.example.hr',
      p_pattern            => 'emp_post_example/',
      p_method             => 'POST',
      p_name               => 'EmpJob',
      p_bind_variable_name => 'ejob',
      p_source_type        => 'HEADER',
      p_param_type         => 'STRING',
      p_access_method      => 'IN',
      p_comments           => NULL);

  ORDS.DEFINE_PARAMETER(
      p_module_name        => 'oracle.example.hr',
      p_pattern            => 'emp_post_example/',
      p_method             => 'POST',
      p_name               => 'EmpMgr',
      p_bind_variable_name => 'mgr',
      p_source_type        => 'HEADER',
      p_param_type         => 'INT',
      p_access_method      => 'IN',
      p_comments           => NULL);

  ORDS.DEFINE_PARAMETER(
      p_module_name        => 'oracle.example.hr',
      p_pattern            => 'emp_post_example/',
      p_method             => 'POST',
      p_name               => 'EmpSal',
      p_bind_variable_name => 'sal',
      p_source_type        => 'HEADER',
      p_param_type         => 'INT',
      p_access_method      => 'IN',
      p_comments           => NULL);

  ORDS.DEFINE_PARAMETER(
      p_module_name        => 'oracle.example.hr',
      p_pattern            => 'emp_post_example/',
      p_method             => 'POST',
      p_name               => 'EmpComm',
      p_bind_variable_name => 'comm',
      p_source_type        => 'HEADER',
      p_param_type         => 'INT',
      p_access_method      => 'IN',
      p_comments           => NULL);

  ORDS.DEFINE_PARAMETER(
      p_module_name        => 'oracle.example.hr',
      p_pattern            => 'emp_post_example/',
      p_method             => 'POST',
      p_name               => 'EmpDept',
      p_bind_variable_name => 'deptno',
      p_source_type        => 'HEADER',
      p_param_type         => 'INT',
      p_access_method      => 'IN',
      p_comments           => NULL);

  ORDS.CREATE_ROLE(
      p_role_name=> 'oracle.dbtools.role.autorest.VERANOLINK');
  ORDS.CREATE_ROLE(
      p_role_name=> 'oracle.dbtools.role.autorest.any.VERANOLINK');
  l_roles(1) := 'oracle.dbtools.auth.roles.builtin.VecDB';
  l_patterns(1) := '/vecdb/*';

  ORDS.DEFINE_PRIVILEGE(
      p_privilege_name => 'oracle.dbtools.auth.privileges.builtin.VecDB',
      p_roles          => l_roles,
      p_patterns       => l_patterns,
      p_modules        => l_modules,
      p_label          => NULL,
      p_description    => NULL,
      p_comments       => NULL); 

  l_roles.DELETE;
  l_modules.DELETE;
  l_patterns.DELETE;

  l_roles(1) := 'oracle.dbtools.autorest.any.schema';
  l_roles(2) := 'oracle.dbtools.role.autorest.VERANOLINK';
  l_patterns(1) := '/metadata-catalog/*';

  ORDS.DEFINE_PRIVILEGE(
      p_privilege_name => 'oracle.dbtools.autorest.privilege.VERANOLINK',
      p_roles          => l_roles,
      p_patterns       => l_patterns,
      p_modules        => l_modules,
      p_label          => 'VERANOLINK metadata-catalog access',
      p_description    => 'Provides access to the metadata catalog of the objects in the VERANOLINK schema.',
      p_comments       => NULL); 

  l_roles.DELETE;
  l_modules.DELETE;
  l_patterns.DELETE;

  l_roles(1) := 'SODA Developer';
  l_patterns(1) := '/soda/*';

  ORDS.DEFINE_PRIVILEGE(
      p_privilege_name => 'oracle.soda.privilege.developer',
      p_roles          => l_roles,
      p_patterns       => l_patterns,
      p_modules        => l_modules,
      p_label          => NULL,
      p_description    => NULL,
      p_comments       => NULL); 

  l_roles.DELETE;
  l_modules.DELETE;
  l_patterns.DELETE;

  ORDS.FINALIZE_IMPORT(
      p_prune => FALSE,
      p_objects => null);

COMMIT;
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    RAISE;

END;
/


-- sqlcl_snapshot {"hash":"132be470ae389c774b55c6aebec4cd1c59014537","type":"ORDS_SCHEMA","name":"ords","schemaName":"VERANOLINK","sxml":""}