﻿/*
** repository: https://github.com/trumanzhao/luna
** trumanzhao, 2016-11-01, trumanzhao@foxmail.com
*/

#pragma once

#include <assert.h>
#include <limits.h>
#include <string.h>

#define IO_BUFFER_DEF 64 * 1024             //64K
#define IO_BUFFER_MAX IO_BUFFER_DEF * 1024  //64M

struct io_buffer
{
    io_buffer() { alloc_buffer(); }
    ~io_buffer() { free(m_buffer); }

    size_t resize(size_t size)
    {
        size_t data_len = (size_t)(m_data_end - m_data_begin);
        if (size == m_buffer_size || size < data_len || size > IO_BUFFER_MAX)
        {
            auto buffer_end = m_buffer + m_buffer_size;
            return buffer_end - m_data_end;
        }
        m_buffer = (BYTE*)realloc(m_buffer, size);
        m_data_end = m_buffer + data_len;
        m_data_begin = m_buffer;
        m_buffer_size = size;
        return m_buffer_size - data_len;
    }

    bool push_data(const void* data, size_t data_len)
    {
        size_t space_len = m_buffer + m_buffer_size - m_data_end;
        assert(space_len >= data_len);
        memcpy(m_data_end, data, data_len);
        m_data_end += data_len;
        return true;
    }

    void pop_data(size_t uLen)
    {
        assert(m_data_begin + uLen <= m_data_end);
        m_data_begin += uLen;
        regularize();

        size_t data_len = (size_t)(m_data_end - m_data_begin);
        if (m_buffer_size > IO_BUFFER_DEF && data_len < m_buffer_size / 4)
        {
            resize(m_buffer_size / 2);
        }
    }

    size_t regularize()
    {
        size_t data_len = (size_t)(m_data_end - m_data_begin);
        if (m_data_begin > m_buffer)
        {
            if (data_len > 0)
            {
                memmove(m_buffer, m_data_begin, data_len);
            }
            m_data_end = m_buffer + data_len;
            m_data_begin = m_buffer;
        }
        return m_buffer_size - data_len;
    }

    void clear()
    {
        resize(IO_BUFFER_DEF);
        m_buffer_size = IO_BUFFER_DEF;
        m_data_begin = m_data_end = m_buffer;
    }

    BYTE* peek_space(size_t* len)
    {
        auto buffer_end = m_buffer + m_buffer_size;
        size_t space_len = buffer_end - m_data_end;
        if (space_len < IO_BUFFER_DEF / 8)
        {
            space_len = resize(m_buffer_size * 2);
        }
        *len = space_len;
        return m_data_end;
    }

    void pop_space(size_t pop_len)
    {
        assert(m_data_end + pop_len <= m_buffer + m_buffer_size);
        m_data_end += pop_len;
    }

    BYTE* peek_data(size_t* data_len)
    {
        *data_len = (size_t)(m_data_end - m_data_begin);
        return m_data_begin;
    }

    bool empty() { return m_data_end <= m_data_begin; }

private:
    void alloc_buffer()
    {
        m_buffer = (BYTE*)malloc(IO_BUFFER_DEF);
        m_buffer_size = IO_BUFFER_DEF;
        m_data_begin = m_buffer;
        m_data_end = m_data_begin;
    }

    BYTE* m_data_begin = nullptr;
    BYTE* m_data_end = nullptr;
    BYTE* m_buffer = nullptr;
    size_t m_buffer_size = 0;
};
