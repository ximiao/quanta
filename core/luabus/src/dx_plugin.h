/**
 * @author: errorcpp@qq.com
 * @date:   2019-07-11
 */

#pragma once

#include <cstdint>
#include "luna.h"
#include "lua_archiver.h"

#define NET_PACKET_MAX_LEN (64*1024-1)

struct dx_pkt_header
{
    uint16_t		len;            // �������ĳ���
    uint8_t   		flag;			// ��־λ
    uint8_t	    	seq_id;			// cli->svr �ͻ����������кţ������������ڷ�ֹ���ط�; svr->cli ����˷����ͻ��˵İ����кţ��ͻ����յ��İ���Ų��������������Ͽ�
    uint32_t		cmd_id;         // Э��ID
    uint32_t		session_id;     // sessionId
};

typedef dx_pkt_header* dx_pkt_header_ptr;
