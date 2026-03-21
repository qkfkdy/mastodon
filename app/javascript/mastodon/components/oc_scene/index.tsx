import { useState, useCallback } from 'react';
import { useDispatch } from 'react-redux';

import { submitOcChoice } from 'mastodon/actions/oc_scene';

interface Choice {
  idx: number;
  label: string;
}

interface OcSceneUIProps {
  sceneId: string;
  choices: Choice[];
  statusId: string;
  botAcct: string;
}

export const OcSceneUI: React.FC<OcSceneUIProps> = ({
  sceneId,
  choices,
  statusId,
  botAcct,
}) => {
  const dispatch = useDispatch();
  const [selectedChoice, setSelectedChoice] = useState<number | null>(null);
  const [actionText, setActionText] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [submitted, setSubmitted] = useState(false);

  const canSubmit = selectedChoice !== null && actionText.trim().length > 0 && !submitting && !submitted;

  const handleSubmit = useCallback(() => {
    if (!canSubmit || selectedChoice === null) return;

    setSubmitting(true);
    dispatch(submitOcChoice(statusId, botAcct, selectedChoice, actionText.trim()))
      .then(() => {
        setSubmitted(true);
      })
      .catch(() => {
        setSubmitting(false);
      });
  }, [dispatch, statusId, botAcct, selectedChoice, actionText, canSubmit]);

  if (submitted) {
    const chosenLabel = choices.find(c => c.idx === selectedChoice)?.label ?? '';
    return (
      <div className='oc-scene-ui oc-scene-ui--submitted'>
        <div className='oc-scene-ui__submitted-info'>
          <span className='oc-scene-ui__submitted-choice'>{selectedChoice}. {chosenLabel}</span>
          <p className='oc-scene-ui__submitted-action'>{actionText}</p>
        </div>
      </div>
    );
  }

  if (choices.length === 0) {
    return null;
  }

  return (
    <div className='oc-scene-ui'>
      <div className='oc-scene-ui__section-label'>행동 선택</div>
      <div className='oc-scene-ui__choices'>
        {choices.map((choice) => (
          <button
            key={choice.idx}
            className={`oc-scene-ui__choice-btn ${selectedChoice === choice.idx ? 'oc-scene-ui__choice-btn--selected' : ''}`}
            onClick={() => setSelectedChoice(choice.idx)}
            disabled={submitting}
          >
            <span className='oc-scene-ui__choice-idx'>{choice.idx}</span>
            <span className='oc-scene-ui__choice-label'>{choice.label}</span>
          </button>
        ))}
      </div>

      <div className='oc-scene-ui__section-label'>캐릭터 액션 지문</div>
      <textarea
        className='oc-scene-ui__action-input'
        placeholder='캐릭터의 행동을 묘사하세요...'
        value={actionText}
        onChange={(e) => setActionText(e.target.value)}
        disabled={submitting}
        rows={3}
      />

      <button
        className='oc-scene-ui__submit'
        onClick={handleSubmit}
        disabled={!canSubmit}
      >
        {submitting ? '전송 중...' : '제출'}
      </button>
    </div>
  );
};
