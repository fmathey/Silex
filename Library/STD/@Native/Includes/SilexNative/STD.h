#ifndef SILEX_NATIVE_STD_H
#define SILEX_NATIVE_STD_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SILEX_NATIVE_TRANSPORT_SILEXNATIVE_STD_CONSOLE_DIMENSIONS 1
typedef struct SilexNative_STD_Console_Dimensions {
    int64_t columns;
    int64_t rows;
} SilexNative_STD_Console_Dimensions;
#define SILEX_NATIVE_TRANSPORT_SILEXNATIVE_STD_CONSOLE_SESSION_NATIVEKEYEVENT 1
typedef struct SilexNative_STD_Console_Session_NativeKeyEvent {
    int64_t code;
    bool shift;
    bool control;
    bool alt;
    int64_t number;
    char* text_bytes;
    int64_t text_length;
} SilexNative_STD_Console_Session_NativeKeyEvent;
#define SILEX_NATIVE_TRANSPORT_SILEXNATIVE_STD_ENVIRONMENT_NATIVELOOKUPRESULT 1
typedef struct SilexNative_STD_Environment_NativeLookupResult {
    bool succeeded;
    int64_t error_kind;
    bool present;
    char* value_bytes;
    int64_t value_length;
    char* detail_bytes;
    int64_t detail_length;
} SilexNative_STD_Environment_NativeLookupResult;
#define SILEX_NATIVE_TRANSPORT_SILEXNATIVE_STD_ENVIRONMENT_NATIVEOPERATIONRESULT 1
typedef struct SilexNative_STD_Environment_NativeOperationResult {
    bool succeeded;
    int64_t error_kind;
    char* detail_bytes;
    int64_t detail_length;
} SilexNative_STD_Environment_NativeOperationResult;
#define SILEX_NATIVE_TRANSPORT_SILEXNATIVE_STD_PATH_NATIVEPATHRESULT 1
typedef struct SilexNative_STD_Path_NativePathResult {
    bool succeeded;
    bool present;
    bool boolean;
    char* text_bytes;
    int64_t text_length;
    char* detail_bytes;
    int64_t detail_length;
} SilexNative_STD_Path_NativePathResult;
typedef struct SilexNative_STD_File_File SilexNative_STD_File_File;
#define SILEX_NATIVE_TRANSPORT_SILEXNATIVE_STD_FILE_NATIVEFAILURE 1
typedef struct SilexNative_STD_File_NativeFailure {
    int64_t kind;
    char* detail_bytes;
    int64_t detail_length;
} SilexNative_STD_File_NativeFailure;
typedef enum SilexNative_STD_File_native_openResultTag {
    SilexNative_STD_File_native_openResultTag_success = 0,
    SilexNative_STD_File_native_openResultTag_failure = 1
} SilexNative_STD_File_native_openResultTag;

typedef struct SilexNative_STD_File_native_openResult {
    SilexNative_STD_File_native_openResultTag tag;
    SilexNative_STD_File_File* success_value;
    SilexNative_STD_File_NativeFailure failure_value;
} SilexNative_STD_File_native_openResult;

typedef enum SilexNative_STD_File_native_closeResultTag {
    SilexNative_STD_File_native_closeResultTag_success = 0,
    SilexNative_STD_File_native_closeResultTag_failure = 1
} SilexNative_STD_File_native_closeResultTag;

typedef struct SilexNative_STD_File_native_closeResult {
    SilexNative_STD_File_native_closeResultTag tag;
    SilexNative_STD_File_NativeFailure failure_value;
} SilexNative_STD_File_native_closeResult;

typedef enum SilexNative_STD_File_native_readResultTag {
    SilexNative_STD_File_native_readResultTag_success = 0,
    SilexNative_STD_File_native_readResultTag_failure = 1
} SilexNative_STD_File_native_readResultTag;

typedef struct SilexNative_STD_File_native_readResult {
    SilexNative_STD_File_native_readResultTag tag;
    int64_t success_value;
    SilexNative_STD_File_NativeFailure failure_value;
} SilexNative_STD_File_native_readResult;

typedef enum SilexNative_STD_File_native_writeResultTag {
    SilexNative_STD_File_native_writeResultTag_success = 0,
    SilexNative_STD_File_native_writeResultTag_failure = 1
} SilexNative_STD_File_native_writeResultTag;

typedef struct SilexNative_STD_File_native_writeResult {
    SilexNative_STD_File_native_writeResultTag tag;
    int64_t success_value;
    SilexNative_STD_File_NativeFailure failure_value;
} SilexNative_STD_File_native_writeResult;

typedef enum SilexNative_STD_File_native_flushResultTag {
    SilexNative_STD_File_native_flushResultTag_success = 0,
    SilexNative_STD_File_native_flushResultTag_failure = 1
} SilexNative_STD_File_native_flushResultTag;

typedef struct SilexNative_STD_File_native_flushResult {
    SilexNative_STD_File_native_flushResultTag tag;
    SilexNative_STD_File_NativeFailure failure_value;
} SilexNative_STD_File_native_flushResult;

typedef enum SilexNative_STD_File_native_seekResultTag {
    SilexNative_STD_File_native_seekResultTag_success = 0,
    SilexNative_STD_File_native_seekResultTag_failure = 1
} SilexNative_STD_File_native_seekResultTag;

typedef struct SilexNative_STD_File_native_seekResult {
    SilexNative_STD_File_native_seekResultTag tag;
    int64_t success_value;
    SilexNative_STD_File_NativeFailure failure_value;
} SilexNative_STD_File_native_seekResult;

typedef enum SilexNative_STD_File_native_positionResultTag {
    SilexNative_STD_File_native_positionResultTag_success = 0,
    SilexNative_STD_File_native_positionResultTag_failure = 1
} SilexNative_STD_File_native_positionResultTag;

typedef struct SilexNative_STD_File_native_positionResult {
    SilexNative_STD_File_native_positionResultTag tag;
    int64_t success_value;
    SilexNative_STD_File_NativeFailure failure_value;
} SilexNative_STD_File_native_positionResult;

typedef enum SilexNative_STD_File_native_lengthResultTag {
    SilexNative_STD_File_native_lengthResultTag_success = 0,
    SilexNative_STD_File_native_lengthResultTag_failure = 1
} SilexNative_STD_File_native_lengthResultTag;

typedef struct SilexNative_STD_File_native_lengthResult {
    SilexNative_STD_File_native_lengthResultTag tag;
    int64_t success_value;
    SilexNative_STD_File_NativeFailure failure_value;
} SilexNative_STD_File_native_lengthResult;

typedef enum SilexNative_STD_File_native_set_lengthResultTag {
    SilexNative_STD_File_native_set_lengthResultTag_success = 0,
    SilexNative_STD_File_native_set_lengthResultTag_failure = 1
} SilexNative_STD_File_native_set_lengthResultTag;

typedef struct SilexNative_STD_File_native_set_lengthResult {
    SilexNative_STD_File_native_set_lengthResultTag tag;
    SilexNative_STD_File_NativeFailure failure_value;
} SilexNative_STD_File_native_set_lengthResult;

#define SILEX_NATIVE_TRANSPORT_SILEXNATIVE_STD_FILESYSTEM_NATIVEMETADATARESULT 1
typedef struct SilexNative_STD_FileSystem_NativeMetadataResult {
    bool succeeded;
    int64_t error_kind;
    int64_t file_kind;
    int64_t size;
    bool readonly;
    char* detail_bytes;
    int64_t detail_length;
} SilexNative_STD_FileSystem_NativeMetadataResult;
#define SILEX_NATIVE_TRANSPORT_SILEXNATIVE_STD_FILESYSTEM_NATIVEPATHRESULT 1
typedef struct SilexNative_STD_FileSystem_NativePathResult {
    bool succeeded;
    int64_t error_kind;
    char* path_bytes;
    int64_t path_length;
    char* detail_bytes;
    int64_t detail_length;
} SilexNative_STD_FileSystem_NativePathResult;
#define SILEX_NATIVE_TRANSPORT_SILEXNATIVE_STD_FILESYSTEM_NATIVEOPERATIONRESULT 1
typedef struct SilexNative_STD_FileSystem_NativeOperationResult {
    bool succeeded;
    int64_t error_kind;
    char* detail_bytes;
    int64_t detail_length;
} SilexNative_STD_FileSystem_NativeOperationResult;
#define SILEX_NATIVE_TRANSPORT_SILEXNATIVE_STD_JSON_NATIVEBUILDFAILURE 1
typedef struct SilexNative_STD_JSON_NativeBuildFailure {
    int64_t kind;
    char* text_bytes;
    int64_t text_length;
} SilexNative_STD_JSON_NativeBuildFailure;
typedef enum SilexNative_STD_JSON_native_number_textResultTag {
    SilexNative_STD_JSON_native_number_textResultTag_success = 0,
    SilexNative_STD_JSON_native_number_textResultTag_failure = 1
} SilexNative_STD_JSON_native_number_textResultTag;

typedef struct SilexNative_STD_JSON_native_number_textResult {
    SilexNative_STD_JSON_native_number_textResultTag tag;
    uint64_t success_value;
    SilexNative_STD_JSON_NativeBuildFailure failure_value;
} SilexNative_STD_JSON_native_number_textResult;

typedef enum SilexNative_STD_JSON_native_number_floatResultTag {
    SilexNative_STD_JSON_native_number_floatResultTag_success = 0,
    SilexNative_STD_JSON_native_number_floatResultTag_failure = 1
} SilexNative_STD_JSON_native_number_floatResultTag;

typedef struct SilexNative_STD_JSON_native_number_floatResult {
    SilexNative_STD_JSON_native_number_floatResultTag tag;
    uint64_t success_value;
    SilexNative_STD_JSON_NativeBuildFailure failure_value;
} SilexNative_STD_JSON_native_number_floatResult;

typedef enum SilexNative_STD_JSON_native_object_appendResultTag {
    SilexNative_STD_JSON_native_object_appendResultTag_success = 0,
    SilexNative_STD_JSON_native_object_appendResultTag_failure = 1
} SilexNative_STD_JSON_native_object_appendResultTag;

typedef struct SilexNative_STD_JSON_native_object_appendResult {
    SilexNative_STD_JSON_native_object_appendResultTag tag;
    SilexNative_STD_JSON_NativeBuildFailure failure_value;
} SilexNative_STD_JSON_native_object_appendResult;

#define SILEX_NATIVE_TRANSPORT_SILEXNATIVE_STD_JSON_NATIVEPARSEFAILURE 1
typedef struct SilexNative_STD_JSON_NativeParseFailure {
    int64_t kind;
    int64_t byte_offset;
    int64_t line;
    int64_t column;
    char* detail_bytes;
    int64_t detail_length;
} SilexNative_STD_JSON_NativeParseFailure;
typedef enum SilexNative_STD_JSON_native_parseResultTag {
    SilexNative_STD_JSON_native_parseResultTag_success = 0,
    SilexNative_STD_JSON_native_parseResultTag_failure = 1
} SilexNative_STD_JSON_native_parseResultTag;

typedef struct SilexNative_STD_JSON_native_parseResult {
    SilexNative_STD_JSON_native_parseResultTag tag;
    uint64_t success_value;
    SilexNative_STD_JSON_NativeParseFailure failure_value;
} SilexNative_STD_JSON_native_parseResult;

#define SILEX_NATIVE_TRANSPORT_SILEXNATIVE_STD_NETWORK_NATIVERESULT 1
typedef struct SilexNative_STD_Network_NativeResult {
    bool succeeded;
    int64_t kind;
    char* detail_bytes;
    int64_t detail_length;
} SilexNative_STD_Network_NativeResult;
typedef struct SilexNative_STD_Network_TCP_Stream SilexNative_STD_Network_TCP_Stream;
typedef struct SilexNative_STD_Network_TCP_Listener SilexNative_STD_Network_TCP_Listener;
#define SILEX_NATIVE_TRANSPORT_SILEXNATIVE_STD_NETWORK_TCP_NATIVEFAILURE 1
typedef struct SilexNative_STD_Network_TCP_NativeFailure {
    int64_t kind;
    char* detail_bytes;
    int64_t detail_length;
} SilexNative_STD_Network_TCP_NativeFailure;
typedef enum SilexNative_STD_Network_TCP_native_connectResultTag {
    SilexNative_STD_Network_TCP_native_connectResultTag_success = 0,
    SilexNative_STD_Network_TCP_native_connectResultTag_failure = 1
} SilexNative_STD_Network_TCP_native_connectResultTag;

typedef struct SilexNative_STD_Network_TCP_native_connectResult {
    SilexNative_STD_Network_TCP_native_connectResultTag tag;
    SilexNative_STD_Network_TCP_Stream* success_value;
    SilexNative_STD_Network_TCP_NativeFailure failure_value;
} SilexNative_STD_Network_TCP_native_connectResult;

typedef enum SilexNative_STD_Network_TCP_native_listenResultTag {
    SilexNative_STD_Network_TCP_native_listenResultTag_success = 0,
    SilexNative_STD_Network_TCP_native_listenResultTag_failure = 1
} SilexNative_STD_Network_TCP_native_listenResultTag;

typedef struct SilexNative_STD_Network_TCP_native_listenResult {
    SilexNative_STD_Network_TCP_native_listenResultTag tag;
    SilexNative_STD_Network_TCP_Listener* success_value;
    SilexNative_STD_Network_TCP_NativeFailure failure_value;
} SilexNative_STD_Network_TCP_native_listenResult;

typedef enum SilexNative_STD_Network_TCP_native_acceptResultTag {
    SilexNative_STD_Network_TCP_native_acceptResultTag_success = 0,
    SilexNative_STD_Network_TCP_native_acceptResultTag_failure = 1
} SilexNative_STD_Network_TCP_native_acceptResultTag;

typedef struct SilexNative_STD_Network_TCP_native_acceptResult {
    SilexNative_STD_Network_TCP_native_acceptResultTag tag;
    SilexNative_STD_Network_TCP_Stream* success_value;
    SilexNative_STD_Network_TCP_NativeFailure failure_value;
} SilexNative_STD_Network_TCP_native_acceptResult;

typedef enum SilexNative_STD_Network_TCP_native_readResultTag {
    SilexNative_STD_Network_TCP_native_readResultTag_success = 0,
    SilexNative_STD_Network_TCP_native_readResultTag_failure = 1
} SilexNative_STD_Network_TCP_native_readResultTag;

typedef struct SilexNative_STD_Network_TCP_native_readResult {
    SilexNative_STD_Network_TCP_native_readResultTag tag;
    int64_t success_value;
    SilexNative_STD_Network_TCP_NativeFailure failure_value;
} SilexNative_STD_Network_TCP_native_readResult;

typedef enum SilexNative_STD_Network_TCP_native_writeResultTag {
    SilexNative_STD_Network_TCP_native_writeResultTag_success = 0,
    SilexNative_STD_Network_TCP_native_writeResultTag_failure = 1
} SilexNative_STD_Network_TCP_native_writeResultTag;

typedef struct SilexNative_STD_Network_TCP_native_writeResult {
    SilexNative_STD_Network_TCP_native_writeResultTag tag;
    int64_t success_value;
    SilexNative_STD_Network_TCP_NativeFailure failure_value;
} SilexNative_STD_Network_TCP_native_writeResult;

typedef enum SilexNative_STD_Network_TCP_native_shutdownResultTag {
    SilexNative_STD_Network_TCP_native_shutdownResultTag_success = 0,
    SilexNative_STD_Network_TCP_native_shutdownResultTag_failure = 1
} SilexNative_STD_Network_TCP_native_shutdownResultTag;

typedef struct SilexNative_STD_Network_TCP_native_shutdownResult {
    SilexNative_STD_Network_TCP_native_shutdownResultTag tag;
    SilexNative_STD_Network_TCP_NativeFailure failure_value;
} SilexNative_STD_Network_TCP_native_shutdownResult;

typedef enum SilexNative_STD_Network_TCP_native_close_streamResultTag {
    SilexNative_STD_Network_TCP_native_close_streamResultTag_success = 0,
    SilexNative_STD_Network_TCP_native_close_streamResultTag_failure = 1
} SilexNative_STD_Network_TCP_native_close_streamResultTag;

typedef struct SilexNative_STD_Network_TCP_native_close_streamResult {
    SilexNative_STD_Network_TCP_native_close_streamResultTag tag;
    SilexNative_STD_Network_TCP_NativeFailure failure_value;
} SilexNative_STD_Network_TCP_native_close_streamResult;

typedef enum SilexNative_STD_Network_TCP_native_close_listenerResultTag {
    SilexNative_STD_Network_TCP_native_close_listenerResultTag_success = 0,
    SilexNative_STD_Network_TCP_native_close_listenerResultTag_failure = 1
} SilexNative_STD_Network_TCP_native_close_listenerResultTag;

typedef struct SilexNative_STD_Network_TCP_native_close_listenerResult {
    SilexNative_STD_Network_TCP_native_close_listenerResultTag tag;
    SilexNative_STD_Network_TCP_NativeFailure failure_value;
} SilexNative_STD_Network_TCP_native_close_listenerResult;

#define SILEX_NATIVE_TRANSPORT_SILEXNATIVE_STD_NETWORK_TCP_NATIVEOPERATION 1
typedef struct SilexNative_STD_Network_TCP_NativeOperation {
    bool succeeded;
    int64_t kind;
    char* detail_bytes;
    int64_t detail_length;
} SilexNative_STD_Network_TCP_NativeOperation;
typedef struct SilexNative_STD_Network_UDP_Socket SilexNative_STD_Network_UDP_Socket;
#define SILEX_NATIVE_TRANSPORT_SILEXNATIVE_STD_NETWORK_UDP_NATIVEFAILURE 1
typedef struct SilexNative_STD_Network_UDP_NativeFailure {
    int64_t kind;
    char* detail_bytes;
    int64_t detail_length;
} SilexNative_STD_Network_UDP_NativeFailure;
typedef enum SilexNative_STD_Network_UDP_native_bindResultTag {
    SilexNative_STD_Network_UDP_native_bindResultTag_success = 0,
    SilexNative_STD_Network_UDP_native_bindResultTag_failure = 1
} SilexNative_STD_Network_UDP_native_bindResultTag;

typedef struct SilexNative_STD_Network_UDP_native_bindResult {
    SilexNative_STD_Network_UDP_native_bindResultTag tag;
    SilexNative_STD_Network_UDP_Socket* success_value;
    SilexNative_STD_Network_UDP_NativeFailure failure_value;
} SilexNative_STD_Network_UDP_native_bindResult;

typedef enum SilexNative_STD_Network_UDP_native_openResultTag {
    SilexNative_STD_Network_UDP_native_openResultTag_success = 0,
    SilexNative_STD_Network_UDP_native_openResultTag_failure = 1
} SilexNative_STD_Network_UDP_native_openResultTag;

typedef struct SilexNative_STD_Network_UDP_native_openResult {
    SilexNative_STD_Network_UDP_native_openResultTag tag;
    SilexNative_STD_Network_UDP_Socket* success_value;
    SilexNative_STD_Network_UDP_NativeFailure failure_value;
} SilexNative_STD_Network_UDP_native_openResult;

typedef enum SilexNative_STD_Network_UDP_native_send_toResultTag {
    SilexNative_STD_Network_UDP_native_send_toResultTag_success = 0,
    SilexNative_STD_Network_UDP_native_send_toResultTag_failure = 1
} SilexNative_STD_Network_UDP_native_send_toResultTag;

typedef struct SilexNative_STD_Network_UDP_native_send_toResult {
    SilexNative_STD_Network_UDP_native_send_toResultTag tag;
    SilexNative_STD_Network_UDP_NativeFailure failure_value;
} SilexNative_STD_Network_UDP_native_send_toResult;

#define SILEX_NATIVE_TRANSPORT_SILEXNATIVE_STD_NETWORK_UDP_NATIVERECEIVEOPERATION 1
typedef struct SilexNative_STD_Network_UDP_NativeReceiveOperation {
    bool succeeded;
    int64_t kind;
    char* detail_bytes;
    int64_t detail_length;
    int64_t count;
    bool truncated;
} SilexNative_STD_Network_UDP_NativeReceiveOperation;
#define SILEX_NATIVE_TRANSPORT_SILEXNATIVE_STD_NETWORK_UDP_NATIVEOPERATION 1
typedef struct SilexNative_STD_Network_UDP_NativeOperation {
    bool succeeded;
    int64_t kind;
    char* detail_bytes;
    int64_t detail_length;
} SilexNative_STD_Network_UDP_NativeOperation;
typedef enum SilexNative_STD_Network_UDP_native_closeResultTag {
    SilexNative_STD_Network_UDP_native_closeResultTag_success = 0,
    SilexNative_STD_Network_UDP_native_closeResultTag_failure = 1
} SilexNative_STD_Network_UDP_native_closeResultTag;

typedef struct SilexNative_STD_Network_UDP_native_closeResult {
    SilexNative_STD_Network_UDP_native_closeResultTag tag;
    SilexNative_STD_Network_UDP_NativeFailure failure_value;
} SilexNative_STD_Network_UDP_native_closeResult;

#define SILEX_NATIVE_TRANSPORT_SILEXNATIVE_STD_PROCESS_NATIVEOPERATIONRESULT 1
typedef struct SilexNative_STD_Process_NativeOperationResult {
    bool succeeded;
    int64_t error_kind;
    char* detail_bytes;
    int64_t detail_length;
} SilexNative_STD_Process_NativeOperationResult;
#define SILEX_NATIVE_TRANSPORT_SILEXNATIVE_STD_PROCESS_NATIVEPATHRESULT 1
typedef struct SilexNative_STD_Process_NativePathResult {
    bool succeeded;
    int64_t error_kind;
    char* path_bytes;
    int64_t path_length;
    char* detail_bytes;
    int64_t detail_length;
} SilexNative_STD_Process_NativePathResult;
typedef struct SilexNative_STD_Subprocess_NativeCommand SilexNative_STD_Subprocess_NativeCommand;
typedef struct SilexNative_STD_Subprocess_NativeOutput SilexNative_STD_Subprocess_NativeOutput;
#define SILEX_NATIVE_TRANSPORT_SILEXNATIVE_STD_SUBPROCESS_NATIVEFAILURE 1
typedef struct SilexNative_STD_Subprocess_NativeFailure {
    int64_t kind;
    char* detail_bytes;
    int64_t detail_length;
} SilexNative_STD_Subprocess_NativeFailure;
typedef enum SilexNative_STD_Subprocess_native_createResultTag {
    SilexNative_STD_Subprocess_native_createResultTag_success = 0,
    SilexNative_STD_Subprocess_native_createResultTag_failure = 1
} SilexNative_STD_Subprocess_native_createResultTag;

typedef struct SilexNative_STD_Subprocess_native_createResult {
    SilexNative_STD_Subprocess_native_createResultTag tag;
    SilexNative_STD_Subprocess_NativeCommand* success_value;
    SilexNative_STD_Subprocess_NativeFailure failure_value;
} SilexNative_STD_Subprocess_native_createResult;

typedef enum SilexNative_STD_Subprocess_native_add_argumentResultTag {
    SilexNative_STD_Subprocess_native_add_argumentResultTag_success = 0,
    SilexNative_STD_Subprocess_native_add_argumentResultTag_failure = 1
} SilexNative_STD_Subprocess_native_add_argumentResultTag;

typedef struct SilexNative_STD_Subprocess_native_add_argumentResult {
    SilexNative_STD_Subprocess_native_add_argumentResultTag tag;
    SilexNative_STD_Subprocess_NativeFailure failure_value;
} SilexNative_STD_Subprocess_native_add_argumentResult;

typedef enum SilexNative_STD_Subprocess_native_set_environmentResultTag {
    SilexNative_STD_Subprocess_native_set_environmentResultTag_success = 0,
    SilexNative_STD_Subprocess_native_set_environmentResultTag_failure = 1
} SilexNative_STD_Subprocess_native_set_environmentResultTag;

typedef struct SilexNative_STD_Subprocess_native_set_environmentResult {
    SilexNative_STD_Subprocess_native_set_environmentResultTag tag;
    SilexNative_STD_Subprocess_NativeFailure failure_value;
} SilexNative_STD_Subprocess_native_set_environmentResult;

typedef enum SilexNative_STD_Subprocess_native_remove_environmentResultTag {
    SilexNative_STD_Subprocess_native_remove_environmentResultTag_success = 0,
    SilexNative_STD_Subprocess_native_remove_environmentResultTag_failure = 1
} SilexNative_STD_Subprocess_native_remove_environmentResultTag;

typedef struct SilexNative_STD_Subprocess_native_remove_environmentResult {
    SilexNative_STD_Subprocess_native_remove_environmentResultTag tag;
    SilexNative_STD_Subprocess_NativeFailure failure_value;
} SilexNative_STD_Subprocess_native_remove_environmentResult;

typedef enum SilexNative_STD_Subprocess_native_set_inputResultTag {
    SilexNative_STD_Subprocess_native_set_inputResultTag_success = 0,
    SilexNative_STD_Subprocess_native_set_inputResultTag_failure = 1
} SilexNative_STD_Subprocess_native_set_inputResultTag;

typedef struct SilexNative_STD_Subprocess_native_set_inputResult {
    SilexNative_STD_Subprocess_native_set_inputResultTag tag;
    SilexNative_STD_Subprocess_NativeFailure failure_value;
} SilexNative_STD_Subprocess_native_set_inputResult;

typedef enum SilexNative_STD_Subprocess_native_runResultTag {
    SilexNative_STD_Subprocess_native_runResultTag_success = 0,
    SilexNative_STD_Subprocess_native_runResultTag_failure = 1
} SilexNative_STD_Subprocess_native_runResultTag;

typedef struct SilexNative_STD_Subprocess_native_runResult {
    SilexNative_STD_Subprocess_native_runResultTag tag;
    SilexNative_STD_Subprocess_NativeOutput* success_value;
    SilexNative_STD_Subprocess_NativeFailure failure_value;
} SilexNative_STD_Subprocess_native_runResult;

uint64_t silexNative_STD_Collections_Hashing_native_hash_str(const char* silexValue108Bytes, int64_t silexValue108Length);
void silexNative_STD_Console_native_move_cursor(int64_t silexValue121, int64_t silexValue122);
void silexNative_STD_Console_native_set_foreground(int64_t silexValue123);
void silexNative_STD_Console_native_set_background(int64_t silexValue124);
void silexNative_STD_Console_native_enable_style(int64_t silexValue125);
void silexNative_STD_Console_write(const char* silexValue126Bytes, int64_t silexValue126Length);
void silexNative_STD_Console_write_line(const char* silexValue127Bytes, int64_t silexValue127Length);
void silexNative_STD_Console_write_error(const char* silexValue128Bytes, int64_t silexValue128Length);
void silexNative_STD_Console_write_error_line(const char* silexValue129Bytes, int64_t silexValue129Length);
void silexNative_STD_Console_flush(void);
bool silexNative_STD_Console_is_interactive(void);
bool silexNative_STD_Console_get_dimensions(SilexNative_STD_Console_Dimensions* output);
void silexNative_STD_Console_clear_screen(void);
void silexNative_STD_Console_clear_line(void);
void silexNative_STD_Console_show_cursor(void);
void silexNative_STD_Console_hide_cursor(void);
void silexNative_STD_Console_reset_style(void);
bool silexNative_STD_Console_read_line(char** output_bytes, int64_t* output_length);
void silexNative_STD_Console_wait_for_enter(void);
int64_t silexNative_STD_Console_Session_native_session_create(void);
void silexNative_STD_Console_Session_native_session_close(int64_t silexValue141);
bool silexNative_STD_Console_Session_native_session_is_open(int64_t silexValue142);
void silexNative_STD_Console_Session_native_session_read(int64_t silexValue143, SilexNative_STD_Console_Session_NativeKeyEvent* output);
bool silexNative_STD_Console_Session_native_session_poll(int64_t silexValue144, int64_t silexValue145, SilexNative_STD_Console_Session_NativeKeyEvent* output);
void silexNative_STD_Console_Session_native_session_enter_alternate_screen(int64_t silexValue146);
void silexNative_STD_Console_Session_native_session_leave_alternate_screen(int64_t silexValue147);
void silexNative_STD_Text_UTF8_native_bytes(const char* silexValue150Bytes, int64_t silexValue150Length, uint8_t** output_bytes, int64_t* output_length);
void silexNative_STD_Text_UTF8_native_string(const uint8_t* silexValue151Values, int64_t silexValue151Count, char** output_bytes, int64_t* output_length);
void silexNative_STD_Environment_native_get(const char* silexValue178Bytes, int64_t silexValue178Length, SilexNative_STD_Environment_NativeLookupResult* output);
void silexNative_STD_Environment_native_set(const char* silexValue179Bytes, int64_t silexValue179Length, const char* silexValue180Bytes, int64_t silexValue180Length, SilexNative_STD_Environment_NativeOperationResult* output);
void silexNative_STD_Environment_native_remove(const char* silexValue181Bytes, int64_t silexValue181Length, SilexNative_STD_Environment_NativeOperationResult* output);
void silexNative_STD_Environment_native_visit_variables(void (*silexValue182)(void*, int64_t, int64_t), void* silexValue182_context, SilexNative_STD_Environment_NativeOperationResult* output);
bool silexNative_STD_Path_native_windows_semantics(void);
void silexNative_STD_Path_native_validate(const char* silexValue214Bytes, int64_t silexValue214Length, bool silexValue215, SilexNative_STD_Path_NativePathResult* output);
void silexNative_STD_Path_native_normalize(const char* silexValue216Bytes, int64_t silexValue216Length, bool silexValue217, SilexNative_STD_Path_NativePathResult* output);
void silexNative_STD_Path_native_join(const char* silexValue218Bytes, int64_t silexValue218Length, const char* silexValue219Bytes, int64_t silexValue219Length, bool silexValue220, SilexNative_STD_Path_NativePathResult* output);
void silexNative_STD_Path_native_parent(const char* silexValue221Bytes, int64_t silexValue221Length, bool silexValue222, SilexNative_STD_Path_NativePathResult* output);
void silexNative_STD_Path_native_name(const char* silexValue223Bytes, int64_t silexValue223Length, bool silexValue224, SilexNative_STD_Path_NativePathResult* output);
void silexNative_STD_Path_native_stem(const char* silexValue225Bytes, int64_t silexValue225Length, bool silexValue226, SilexNative_STD_Path_NativePathResult* output);
void silexNative_STD_Path_native_extension(const char* silexValue227Bytes, int64_t silexValue227Length, bool silexValue228, SilexNative_STD_Path_NativePathResult* output);
void silexNative_STD_Path_native_is_absolute(const char* silexValue229Bytes, int64_t silexValue229Length, bool silexValue230, SilexNative_STD_Path_NativePathResult* output);
void silexNative_STD_File_discard_file(SilexNative_STD_File_File* silexValue258);
void silexNative_STD_File_native_open(const char* silexValue259Bytes, int64_t silexValue259Length, int64_t silexValue260, int64_t silexValue261, bool silexValue262, SilexNative_STD_File_native_openResult* output);
void silexNative_STD_File_native_close(SilexNative_STD_File_File* silexValue263, SilexNative_STD_File_native_closeResult* output);
void silexNative_STD_File_native_read(SilexNative_STD_File_File* silexValue264, uint8_t* silexValue265Values, int64_t silexValue265Count, SilexNative_STD_File_native_readResult* output);
void silexNative_STD_File_native_write(SilexNative_STD_File_File* silexValue266, const uint8_t* silexValue267Values, int64_t silexValue267Count, SilexNative_STD_File_native_writeResult* output);
void silexNative_STD_File_native_flush(SilexNative_STD_File_File* silexValue268, SilexNative_STD_File_native_flushResult* output);
void silexNative_STD_File_native_seek(SilexNative_STD_File_File* silexValue269, int64_t silexValue270, int64_t silexValue271, SilexNative_STD_File_native_seekResult* output);
void silexNative_STD_File_native_position(SilexNative_STD_File_File* silexValue272, SilexNative_STD_File_native_positionResult* output);
void silexNative_STD_File_native_length(SilexNative_STD_File_File* silexValue273, SilexNative_STD_File_native_lengthResult* output);
void silexNative_STD_File_native_set_length(SilexNative_STD_File_File* silexValue274, int64_t silexValue275, SilexNative_STD_File_native_set_lengthResult* output);
void silexNative_STD_FileSystem_native_metadata(const char* silexValue343Bytes, int64_t silexValue343Length, bool silexValue344, SilexNative_STD_FileSystem_NativeMetadataResult* output);
void silexNative_STD_FileSystem_native_canonicalize(const char* silexValue345Bytes, int64_t silexValue345Length, SilexNative_STD_FileSystem_NativePathResult* output);
void silexNative_STD_FileSystem_native_visit_entries(const char* silexValue346Bytes, int64_t silexValue346Length, void (*silexValue347)(void*, int64_t, int64_t), void* silexValue347_context, SilexNative_STD_FileSystem_NativeOperationResult* output);
void silexNative_STD_FileSystem_native_create_directory(const char* silexValue348Bytes, int64_t silexValue348Length, bool silexValue349, SilexNative_STD_FileSystem_NativeOperationResult* output);
void silexNative_STD_FileSystem_native_remove(const char* silexValue350Bytes, int64_t silexValue350Length, bool silexValue351, SilexNative_STD_FileSystem_NativeOperationResult* output);
void silexNative_STD_FileSystem_native_rename(const char* silexValue352Bytes, int64_t silexValue352Length, const char* silexValue353Bytes, int64_t silexValue353Length, SilexNative_STD_FileSystem_NativeOperationResult* output);
void silexNative_STD_FileSystem_native_copy_file(const char* silexValue354Bytes, int64_t silexValue354Length, const char* silexValue355Bytes, int64_t silexValue355Length, bool silexValue356, SilexNative_STD_FileSystem_NativeOperationResult* output);
void silexNative_STD_FileSystem_native_set_readonly(const char* silexValue357Bytes, int64_t silexValue357Length, bool silexValue358, SilexNative_STD_FileSystem_NativeOperationResult* output);
void silexNative_STD_JSON_native_release(uint64_t silexValue405);
uint64_t silexNative_STD_JSON_native_null(void);
uint64_t silexNative_STD_JSON_native_boolean(bool silexValue406);
uint64_t silexNative_STD_JSON_native_string(const char* silexValue407Bytes, int64_t silexValue407Length);
void silexNative_STD_JSON_native_number_text(const char* silexValue408Bytes, int64_t silexValue408Length, SilexNative_STD_JSON_native_number_textResult* output);
uint64_t silexNative_STD_JSON_native_number_int(int64_t silexValue409);
uint64_t silexNative_STD_JSON_native_number_uint(uint64_t silexValue410);
void silexNative_STD_JSON_native_number_float(double silexValue411, SilexNative_STD_JSON_native_number_floatResult* output);
uint64_t silexNative_STD_JSON_native_array(void);
void silexNative_STD_JSON_native_array_append(uint64_t silexValue412, uint64_t silexValue413);
uint64_t silexNative_STD_JSON_native_object(void);
void silexNative_STD_JSON_native_object_append(uint64_t silexValue414, const char* silexValue415Bytes, int64_t silexValue415Length, uint64_t silexValue416, SilexNative_STD_JSON_native_object_appendResult* output);
int64_t silexNative_STD_JSON_native_kind(uint64_t silexValue417);
bool silexNative_STD_JSON_native_boolean_value(uint64_t silexValue418);
void silexNative_STD_JSON_native_text_value(uint64_t silexValue419, char** output_bytes, int64_t* output_length);
int64_t silexNative_STD_JSON_native_count(uint64_t silexValue420);
uint64_t silexNative_STD_JSON_native_child(uint64_t silexValue421, int64_t silexValue422);
void silexNative_STD_JSON_native_member_name(uint64_t silexValue423, int64_t silexValue424, char** output_bytes, int64_t* output_length);
void silexNative_STD_JSON_native_parse(const char* silexValue425Bytes, int64_t silexValue425Length, int64_t silexValue426, SilexNative_STD_JSON_native_parseResult* output);
void silexNative_STD_JSON_native_stringify(uint64_t silexValue427, bool silexValue428, char** output_bytes, int64_t* output_length);
float silexNative_STD_Math_sqrt(float silexValue438);
float silexNative_STD_Math_sin(float silexValue439);
float silexNative_STD_Math_cos(float silexValue440);
float silexNative_STD_Math_tan(float silexValue441);
float silexNative_STD_Math_asin(float silexValue442);
float silexNative_STD_Math_atan2(float silexValue443, float silexValue444);
void silexNative_STD_Network_native_parse_ip(const char* silexValue467Bytes, int64_t silexValue467Length, void (*silexValue468)(void*, int64_t), void* silexValue468_context, SilexNative_STD_Network_NativeResult* output);
void silexNative_STD_Network_native_format_ip(int64_t silexValue469, const uint8_t* silexValue470Values, int64_t silexValue470Count, char** output_bytes, int64_t* output_length);
void silexNative_STD_Network_native_format_endpoint(int64_t silexValue471, int64_t silexValue472, int64_t silexValue473, const uint8_t* silexValue474Values, int64_t silexValue474Count, char** output_bytes, int64_t* output_length);
void silexNative_STD_Network_native_resolve(const char* silexValue475Bytes, int64_t silexValue475Length, int64_t silexValue476, int64_t silexValue477, int64_t silexValue478, void (*silexValue479)(void*, int64_t), void* silexValue479_context, SilexNative_STD_Network_NativeResult* output);
int64_t silexNative_STD_Time_Internal_native_monotonic_microseconds(void);
void silexNative_STD_Network_TCP_discard_stream(SilexNative_STD_Network_TCP_Stream* silexValue534);
void silexNative_STD_Network_TCP_discard_listener(SilexNative_STD_Network_TCP_Listener* silexValue535);
void silexNative_STD_Network_TCP_native_connect(int64_t silexValue536, const uint8_t* silexValue537Values, int64_t silexValue537Count, int64_t silexValue538, int64_t silexValue539, int64_t silexValue540, int64_t silexValue541, int64_t silexValue542, SilexNative_STD_Network_TCP_native_connectResult* output);
void silexNative_STD_Network_TCP_native_listen(int64_t silexValue543, const uint8_t* silexValue544Values, int64_t silexValue544Count, int64_t silexValue545, int64_t silexValue546, int64_t silexValue547, SilexNative_STD_Network_TCP_native_listenResult* output);
void silexNative_STD_Network_TCP_native_accept(SilexNative_STD_Network_TCP_Listener* silexValue548, int64_t silexValue549, int64_t silexValue550, int64_t silexValue551, SilexNative_STD_Network_TCP_native_acceptResult* output);
void silexNative_STD_Network_TCP_native_read(SilexNative_STD_Network_TCP_Stream* silexValue552, uint8_t* silexValue553Values, int64_t silexValue553Count, SilexNative_STD_Network_TCP_native_readResult* output);
void silexNative_STD_Network_TCP_native_write(SilexNative_STD_Network_TCP_Stream* silexValue554, const uint8_t* silexValue555Values, int64_t silexValue555Count, SilexNative_STD_Network_TCP_native_writeResult* output);
void silexNative_STD_Network_TCP_native_shutdown(SilexNative_STD_Network_TCP_Stream* silexValue556, bool silexValue557, SilexNative_STD_Network_TCP_native_shutdownResult* output);
void silexNative_STD_Network_TCP_native_close_stream(SilexNative_STD_Network_TCP_Stream* silexValue558, SilexNative_STD_Network_TCP_native_close_streamResult* output);
void silexNative_STD_Network_TCP_native_close_listener(SilexNative_STD_Network_TCP_Listener* silexValue559, SilexNative_STD_Network_TCP_native_close_listenerResult* output);
void silexNative_STD_Network_TCP_native_stream_endpoint(const SilexNative_STD_Network_TCP_Stream* silexValue560, bool silexValue561, void (*silexValue562)(void*, int64_t), void* silexValue562_context, SilexNative_STD_Network_TCP_NativeOperation* output);
void silexNative_STD_Network_TCP_native_listener_endpoint(const SilexNative_STD_Network_TCP_Listener* silexValue563, void (*silexValue564)(void*, int64_t), void* silexValue564_context, SilexNative_STD_Network_TCP_NativeOperation* output);
void silexNative_STD_Network_TCP_native_subject(const char* silexValue565Bytes, int64_t silexValue565Length, int64_t silexValue566, char** output_bytes, int64_t* output_length);
void silexNative_STD_Network_UDP_discard_socket(SilexNative_STD_Network_UDP_Socket* silexValue696);
void silexNative_STD_Network_UDP_native_bind(int64_t silexValue697, const uint8_t* silexValue698Values, int64_t silexValue698Count, int64_t silexValue699, int64_t silexValue700, int64_t silexValue701, int64_t silexValue702, SilexNative_STD_Network_UDP_native_bindResult* output);
void silexNative_STD_Network_UDP_native_open(int64_t silexValue703, int64_t silexValue704, int64_t silexValue705, SilexNative_STD_Network_UDP_native_openResult* output);
void silexNative_STD_Network_UDP_native_send_to(SilexNative_STD_Network_UDP_Socket* silexValue706, const uint8_t* silexValue707Values, int64_t silexValue707Count, int64_t silexValue708, const uint8_t* silexValue709Values, int64_t silexValue709Count, int64_t silexValue710, int64_t silexValue711, SilexNative_STD_Network_UDP_native_send_toResult* output);
void silexNative_STD_Network_UDP_native_receive_from(SilexNative_STD_Network_UDP_Socket* silexValue712, uint8_t* silexValue713Values, int64_t silexValue713Count, void (*silexValue714)(void*, int64_t), void* silexValue714_context, SilexNative_STD_Network_UDP_NativeReceiveOperation* output);
void silexNative_STD_Network_UDP_native_local_endpoint(const SilexNative_STD_Network_UDP_Socket* silexValue715, void (*silexValue716)(void*, int64_t), void* silexValue716_context, SilexNative_STD_Network_UDP_NativeOperation* output);
void silexNative_STD_Network_UDP_native_close(SilexNative_STD_Network_UDP_Socket* silexValue717, SilexNative_STD_Network_UDP_native_closeResult* output);
void silexNative_STD_Process_native_visit_arguments(void (*silexValue804)(void*, int64_t, int64_t), void* silexValue804_context, SilexNative_STD_Process_NativeOperationResult* output);
void silexNative_STD_Process_native_current_directory(SilexNative_STD_Process_NativePathResult* output);
void silexNative_STD_Process_native_set_current_directory(const char* silexValue805Bytes, int64_t silexValue805Length, SilexNative_STD_Process_NativeOperationResult* output);
void silexNative_STD_Process_native_executable_path(SilexNative_STD_Process_NativePathResult* output);
uint64_t silexNative_STD_Process_native_id(void);
int64_t silexNative_STD_Randomizer_native_seed(void);
void silexNative_STD_Subprocess_discard_command(SilexNative_STD_Subprocess_NativeCommand* silexValue832);
void silexNative_STD_Subprocess_discard_output(SilexNative_STD_Subprocess_NativeOutput* silexValue833);
void silexNative_STD_Subprocess_native_create(const char* silexValue834Bytes, int64_t silexValue834Length, bool silexValue835, const char* silexValue836Bytes, int64_t silexValue836Length, bool silexValue837, int64_t silexValue838, SilexNative_STD_Subprocess_native_createResult* output);
void silexNative_STD_Subprocess_native_add_argument(SilexNative_STD_Subprocess_NativeCommand* silexValue839, const char* silexValue840Bytes, int64_t silexValue840Length, SilexNative_STD_Subprocess_native_add_argumentResult* output);
void silexNative_STD_Subprocess_native_set_environment(SilexNative_STD_Subprocess_NativeCommand* silexValue841, const char* silexValue842Bytes, int64_t silexValue842Length, const char* silexValue843Bytes, int64_t silexValue843Length, SilexNative_STD_Subprocess_native_set_environmentResult* output);
void silexNative_STD_Subprocess_native_remove_environment(SilexNative_STD_Subprocess_NativeCommand* silexValue844, const char* silexValue845Bytes, int64_t silexValue845Length, SilexNative_STD_Subprocess_native_remove_environmentResult* output);
void silexNative_STD_Subprocess_native_set_input(SilexNative_STD_Subprocess_NativeCommand* silexValue846, const uint8_t* silexValue847Values, int64_t silexValue847Count, SilexNative_STD_Subprocess_native_set_inputResult* output);
void silexNative_STD_Subprocess_native_run(SilexNative_STD_Subprocess_NativeCommand* silexValue848, SilexNative_STD_Subprocess_native_runResult* output);
int64_t silexNative_STD_Subprocess_native_status_kind(SilexNative_STD_Subprocess_NativeOutput* silexValue849);
int64_t silexNative_STD_Subprocess_native_status_code(SilexNative_STD_Subprocess_NativeOutput* silexValue850);
void silexNative_STD_Subprocess_native_visit_bytes(SilexNative_STD_Subprocess_NativeOutput* silexValue851, int64_t silexValue852, void (*silexValue853)(void*, int64_t), void* silexValue853_context);
void silexNative_STD_Text_native_normalize(const char* silexValue893Bytes, int64_t silexValue893Length, int64_t silexValue894, char** output_bytes, int64_t* output_length);
void silexNative_STD_Text_native_lowercase(const char* silexValue895Bytes, int64_t silexValue895Length, char** output_bytes, int64_t* output_length);
void silexNative_STD_Text_native_uppercase(const char* silexValue896Bytes, int64_t silexValue896Length, char** output_bytes, int64_t* output_length);
void silexNative_STD_Text_native_case_fold(const char* silexValue897Bytes, int64_t silexValue897Length, char** output_bytes, int64_t* output_length);
void silexNative_STD_Text_Grapheme_native_visit_boundaries(const char* silexValue907Bytes, int64_t silexValue907Length, void (*silexValue908)(void*, int64_t), void* silexValue908_context);
void silexNative_STD_Text_Grapheme_native_slice(const char* silexValue909Bytes, int64_t silexValue909Length, int64_t silexValue910, int64_t silexValue911, char** output_bytes, int64_t* output_length);

#ifdef __cplusplus
}
#endif

#endif
