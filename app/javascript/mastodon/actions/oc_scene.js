import api from '../api';

export function submitOcChoice(statusId, botAcct, choiceIdx, actionText) {
  return () => {
    const mentionText = `@${botAcct} [${choiceIdx}] ${actionText}`;

    return api().request({
      url: '/api/v1/statuses',
      method: 'post',
      data: {
        status: mentionText,
        visibility: 'direct',
        in_reply_to_id: statusId,
      },
    });
  };
}
