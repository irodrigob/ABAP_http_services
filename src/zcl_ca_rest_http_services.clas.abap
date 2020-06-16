CLASS zcl_ca_rest_http_services DEFINITION
  PUBLIC
  INHERITING FROM zcl_ca_http_services
  CREATE PROTECTED .

  PUBLIC SECTION.

  PROTECTED SECTION.
    TYPES: BEGIN OF ts_request_rest,
             request_type TYPE string,
             BEGIN OF post,
               body TYPE string,
             END OF post,
             BEGIN OF multipart,
               name         TYPE string,
               content_file TYPE xstring,
               filename     TYPE string,
               mimetype     TYPE string,
             END OF multipart,
           END OF ts_request_rest.
    TYPES: BEGIN OF ts_response_rest,
             response       TYPE string,
*             http_code        TYPE string,
*             http_status_text TYPE string,
             content_length TYPE string,
             content_type   TYPE string,
           END OF ts_response_rest.

    DATA mo_rest_client TYPE REF TO cl_rest_http_client.
    METHODS create_rest_client
      IMPORTING
                iv_host     TYPE string
                iv_is_https TYPE abap_bool
      RAISING   zcx_ca_rest_http_services.
    METHODS create_rest_client_by_url
      IMPORTING
                iv_url TYPE string
      RAISING   zcx_ca_rest_http_services.
    "! <p class="shorttext synchronized" lang="en">Send request</p>
    "! The values to send can be of the types:
    "!- POST which is a JSON in the message body
    "! - MULTIPART, which is a file
    "! @parameter is_values | <p class="shorttext synchronized" lang="en">Values to send </p>
    "! @raising zcx_ca_rest_http_services | <p class="shorttext synchronized" lang="en"></p>
    METHODS send_request
      IMPORTING
                is_request TYPE ts_request_rest
      RAISING   zcx_ca_rest_http_services.
    METHODS request_json
      IMPORTING
                is_values  TYPE ts_request_rest-post
      CHANGING  co_request TYPE REF TO if_rest_entity .
    METHODS request_multipart
      IMPORTING
        is_values  TYPE ts_request_rest-multipart
      CHANGING
        co_request TYPE REF TO if_rest_entity.
    METHODS get_response
      EXPORTING es_response TYPE ts_response_rest
      RAISING   zcx_ca_rest_http_services.
  PRIVATE SECTION.
ENDCLASS.



CLASS ZCL_CA_REST_HTTP_SERVICES IMPLEMENTATION.


  METHOD create_rest_client.
    " Primero se crea el client HTTP
    create_http_client( EXPORTING iv_host = iv_host
                                  iv_is_https = iv_is_https ).

    " Se crea el client REST pasandole la clase HTTP
    mo_rest_client = NEW cl_rest_http_client( mo_http_client ).

  ENDMETHOD.


  METHOD create_rest_client_by_url.
    " Primero se crea el client HTTP
    create_http_client_by_url( EXPORTING iv_url = iv_url ).

    " Se crea el client REST pasandole la clase HTTP
    mo_rest_client = NEW cl_rest_http_client( mo_http_client ).
  ENDMETHOD.


  METHOD get_response.
    CLEAR: es_response.
    " Se recupera la respuesta de la entidad
    DATA(lo_response) = mo_rest_client->if_rest_client~get_response_entity( ).

    DATA(lv_status_code) = lo_response->get_header_field( '~status_code' ).
    DATA(lv_status_text) = lo_response->get_header_field( '~status_reason' ).
    es_response-content_length = lo_response->get_header_field( 'content-length' ).
    es_response-content_type = lo_response->get_header_field( 'content-type' ).
    "     location = lo_response->get_header_field( 'location' ).
    " Si el status de la llamada no es ni 200 ni 201 se lanza excepción porque se ha producido un error en la recepción
    IF lv_status_code NE '200' AND lv_status_code NE '201'.
      RAISE EXCEPTION TYPE zcx_ca_rest_http_services
        EXPORTING
          textid              = zcx_ca_http_services=>receive_error
          mv_status_code      = lv_status_code
          mv_status_text      = lv_status_text
          mv_content_response = lo_response->get_string_data( ).
    ENDIF.
    es_response-response = lo_response->get_string_data( ).
  ENDMETHOD.


  METHOD request_json.
    co_request->set_string_data( is_values-body ).
  ENDMETHOD.


  METHOD request_multipart.
    DATA(lo_post_file) = NEW cl_rest_multipart_form_data( co_request ).

    lo_post_file->set_file( iv_name = is_values-name
                            iv_filename = is_values-filename
                            iv_type = is_values-mimetype
                            iv_data = is_values-content_file ).

    lo_post_file->if_rest_entity_provider~write_to( co_request ).
  ENDMETHOD.


  METHOD send_request.

    TRY.
        " Se crea la entidad para poder enviar los datos
        DATA(lo_request) = mo_rest_client->if_rest_client~create_request_entity( ).

        lo_request->set_content_type( is_request-request_type ).

        " Se llama al método encargado de alimentar la entidad según el tipo de llamada
        CASE is_request-request_type.
          WHEN if_rest_media_type=>gc_appl_json.
            request_json( EXPORTING is_values = is_request-post
                          CHANGING co_request = lo_request ).

          WHEN if_rest_media_type=>gc_multipart_form_data.
            request_multipart( EXPORTING is_values = is_request-multipart
                                  CHANGING co_request = lo_request ).
        ENDCASE.

        " Según el tipo de envio la entidad se llamará como el método HTTP apropiado
        CASE is_request-request_type.
          WHEN if_rest_media_type=>gc_appl_json OR if_rest_media_type=>gc_multipart_form_data.
            mo_rest_client->if_rest_resource~post( lo_request ).
        ENDCASE.
      CATCH cx_rest_client_exception INTO DATA(lo_excep).
        RAISE EXCEPTION TYPE zcx_ca_rest_http_services
          EXPORTING
            textid = zcx_ca_rest_http_services=>error_send_data.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
