CLASS zcl_ca_http_services DEFINITION
  PUBLIC
  CREATE PUBLIC .

  PUBLIC SECTION.
  PROTECTED SECTION.

    DATA mo_http_client TYPE REF TO if_http_client .

    METHODS set_header_value
      IMPORTING
        !iv_name  TYPE any
        !iv_value TYPE any .
    METHODS set_form_value
      IMPORTING
        !iv_name  TYPE any
        !iv_value TYPE any .
    METHODS set_request_uri
      IMPORTING
        !iv_uri TYPE string .
    METHODS set_token_auth
      IMPORTING
        !iv_token TYPE string .
    METHODS create_http_client
      IMPORTING
        !iv_client   TYPE string
        !iv_is_https TYPE abap_bool .
    METHODS set_request_method
      IMPORTING
        !iv_method TYPE any .
    METHODS set_content_type
      IMPORTING
        !iv_type TYPE char01 .
    METHODS set_request_data
      IMPORTING
        !iv_data                TYPE any
        !iv_pretty_name         TYPE /ui2/cl_json=>pretty_name_mode OPTIONAL
        !iv_convert_data_2_json TYPE sap_bool DEFAULT abap_false .
    METHODS send
      IMPORTING
        !iv_data                TYPE data OPTIONAL
        !iv_pretty_name         TYPE /ui2/cl_json=>pretty_name_mode OPTIONAL
        !iv_convert_data_2_json TYPE sap_bool DEFAULT abap_false .
    METHODS receive
      IMPORTING
        !iv_pretty_name TYPE /ui2/cl_json=>pretty_name_mode OPTIONAL
      EXPORTING
        !ev_data        TYPE data
      RAISING
        zcx_ca_http_services .
    METHODS set_data
      IMPORTING
        iv_data   TYPE xstring
        iv_length TYPE i OPTIONAL.
  PRIVATE SECTION.

ENDCLASS.



CLASS zcl_ca_http_services IMPLEMENTATION.


  METHOD create_http_client.
    DATA: lv_scheme TYPE i.

    IF iv_is_https EQ abap_true.
      lv_scheme = cl_http_client=>schemetype_https.
    ELSE.
      lv_scheme = cl_http_client=>schemetype_http.
    ENDIF.


    CALL METHOD cl_http_client=>create
      EXPORTING
        host               = iv_client
        scheme             = lv_scheme
      IMPORTING
        client             = mo_http_client
      EXCEPTIONS
        argument_not_found = 1
        plugin_not_active  = 2
        internal_error     = 3
        OTHERS             = 4.

    IF sy-subrc NE 0.
      DATA(lo_error) = zcx_ca_reuse_error=>gen_syst(  ).
      RAISE EXCEPTION lo_error.
    ENDIF.

  ENDMETHOD.


  METHOD receive.

    CLEAR ev_data.

    mo_http_client->receive(
      EXCEPTIONS
        http_communication_failure = 1
        http_invalid_state         = 2
        http_processing_failed     = 3
        OTHERS                     = 4 ).

    IF sy-subrc NE 0. " Si hay error no lanzo a excepción salvo que no se puede recuperar bien el status_code.
      DATA(ls_return) = zcl_ca_utilidades=>fill_return( i_type       = sy-msgty
                                                        i_id         = sy-msgid
                                                        i_number     = sy-msgno
                                                        i_message_v1 = sy-msgv1
                                                        i_message_v2 = sy-msgv2
                                                        i_message_v3 = sy-msgv3
                                                        i_message_v4 = sy-msgv4 ).
    ENDIF.

* Obtengo el resultado de la petición. Si todo va bien el codigo ha de ser 200.
    CALL METHOD mo_http_client->response->get_status
      IMPORTING
        code   = DATA(lv_status_code)
        reason = DATA(lv_status_text).

* Recupero el contenido. Si hay ido bien recupero los datos y si ha ido mal el mensaje de error
    DATA(lv_content) = mo_http_client->response->get_cdata( ).


* Si no hay código de status y se ha producido un error en la recepcion devuelvo ese posible
    IF lv_status_code IS INITIAL AND ls_return IS NOT INITIAL.

      RAISE EXCEPTION TYPE zcx_ca_http_services
        EXPORTING
          textid             = zcx_ca_http_services=>receive_error
          ms_return_response = ls_return.

    ELSEIF lv_status_code NE '200' AND lv_status_code NE '201'.

      RAISE EXCEPTION TYPE zcx_ca_http_services
        EXPORTING
          textid              = zcx_ca_http_services=>receive_error
          mv_status_code      = CONV #( lv_status_code )
          mv_status_text      = lv_status_text
          mv_content_response = lv_content.

    ENDIF.


* Miro que tipo de datos me han pasado.
    DATA(lo_data) = cl_abap_typedescr=>describe_by_data( ev_data ).

* Si es estructura o tabla de diccionario entonces convierto la respuesta a los datos pasados. En caso contrario
* lo devuelvo tal cual
    IF lo_data->kind = cl_abap_typedescr=>kind_struct OR lo_data->kind = cl_abap_typedescr=>kind_table.
      /ui2/cl_json=>deserialize( EXPORTING json = lv_content pretty_name = iv_pretty_name CHANGING data = ev_data ).
    ELSE.
      ev_data = lv_content.
    ENDIF.
  ENDMETHOD.


  METHOD send.

* Si se le pasan datos, llamo al método para pasar los datos
    IF iv_data IS NOT INITIAL.
      set_request_data( iv_data = iv_data iv_pretty_name = iv_pretty_name iv_convert_data_2_json = iv_convert_data_2_json ).
    ENDIF.

    mo_http_client->send(
      EXCEPTIONS
        http_communication_failure = 1
        http_invalid_state         = 2
        http_processing_failed     = 3
        http_invalid_timeout       = 4
        OTHERS                     = 5 ).
    IF sy-subrc <> 0.
      DATA(lo_error) = zcx_ca_reuse_error=>gen_syst(  ).
      RAISE EXCEPTION lo_error.
    ENDIF.

  ENDMETHOD.


  METHOD set_content_type.
    DATA lv_content_type TYPE string.
    CASE iv_type.
      WHEN 'X'.
        lv_content_type = |application/x-www-form-urlencoded|.
      WHEN 'J'.
        lv_content_type = |application/json|.
      WHEN 'j'.
        lv_content_type = |application/json;charset=utf-8|.
      WHEN OTHERS.

    ENDCASE.

    CALL METHOD mo_http_client->request->set_header_field
      EXPORTING
        name  = 'Content-type'
        value = lv_content_type.

  ENDMETHOD.


  METHOD set_data.
    DATA lv_length TYPE i.

    IF iv_length IS SUPPLIED.
      lv_length = iv_length.
    ELSE.
      lv_length = xstrlen( iv_data ).
    ENDIF.

    mo_http_client->request->if_http_entity~set_data( EXPORTING data = iv_data
                                                                length = lv_length ).

  ENDMETHOD.


  METHOD set_form_value.
    DATA lv_name TYPE string.
    DATA lv_value TYPE string.

    lv_name = iv_name.
    lv_value = iv_value.

    mo_http_client->request->if_http_entity~set_form_field( name  = lv_name
                                                            value = lv_value ).

  ENDMETHOD.


  METHOD set_header_value.
    DATA lv_name TYPE string.
    DATA lv_value TYPE string.

    lv_name = iv_name.
    lv_value = iv_value.

    CALL METHOD mo_http_client->request->set_header_field
      EXPORTING
        name  = lv_name
        value = lv_value.

  ENDMETHOD.


  METHOD set_request_data.

* Pasamos los datos a formato JSON si se especifica en la cabecera. Esto permite pasar, o bien, estructuras de diccionario, o bien,
* el json directamente.
    IF iv_convert_data_2_json = abap_true.
      DATA(lv_json) = /ui2/cl_json=>serialize( data = iv_data compress = abap_true pretty_name = iv_pretty_name ).
    ELSE.
      lv_json = iv_data.
    ENDIF.

* Pasa los datos del JSON
    CALL METHOD mo_http_client->request->set_cdata
      EXPORTING
        data = lv_json.

  ENDMETHOD.


  METHOD set_request_method.

    CALL METHOD mo_http_client->request->set_header_field
      EXPORTING
        name  = '~request_method'
        value = iv_method.

  ENDMETHOD.


  METHOD set_request_uri.

    cl_http_utility=>set_request_uri(
          request = mo_http_client->request
          uri     = iv_uri ).

  ENDMETHOD.


  METHOD set_token_auth.

    set_header_value( EXPORTING iv_name = 'Authorization' iv_value = iv_token ). "|{ ms_token-token_type CASE = LOWER } { ms_token-access_token }| ).

  ENDMETHOD.
ENDCLASS.
