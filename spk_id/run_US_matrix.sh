#!/bin/bash

#SBATCH -p veu
#SBATCH -c1
#SBATCH --mem 15G
#SBATCH --gres=gpu:1


function print_usage {
	echo "Usage: $0 <unsupervised_guia> <ue_matrix_file>"
}

if [ $# -lt 2 ]; then
	echo "ERROR: Not enough input arguments!"
	print_usage
	exit 1
fi

# read guia line
#GUIA="ablation8_U.guia"
GUIA="$1"
LINE=`sed "${SLURM_ARRAY_TASK_ID}q;d" $GUIA`

IFS=' ' read -r -a params <<< $LINE

UEPOCH="${params[0]}"
UCKPT="${params[1]}"
SEPOCHS="${params[@]:2}"

UE_MATRIX_FILE="$2"

# DATASET params
SPK2IDX="../data/interface/inter1en/interface_dict.npy"
DATA_ROOT="../data/interface/inter1en/all_wav"
TRAIN_GUIA="../data/interface/inter1en/interface_tr.scp"
TEST_GUIA="../data/interface/inter1en/interface_te.scp"
# root to store all supervised ckpts
SAVE_ROOT="US_interface_ckpts/"

#SPK2IDX="../data/VCTK/spk_id/vctk_dict.npy"
#DATA_ROOT="../data/VCTK/spk_id/all_trimmed_wav16"
#TRAIN_GUIA="../data/VCTK/spk_id/vctk_tr.scp"
#TEST_GUIA="../data/VCTK/spk_id/vctk_te.scp"
# root to store all supervised ckpts
#SAVE_ROOT="US_vctk_ckpts/"

UROOT_PATH="../ckpts_ablation8_outnorm_lrdec05"

# supervised model params
SUP_MODEL="mlp"
EPOCH=80
SCHED_MODE="step"
HIDDEN_SIZE=2048
LRDEC=0.5
SEED=4
# WARNING: SET THIS CORRECTLY
EMB_DIM=100
# TODO: --no-valid indicates to not make a validation partition
VALIDATION=""
# only used with validation
PATIENCE=5
OPT="adam"
BATCH_SIZE=100
LOG_FREQ=50
LR=0.001
RNN="--no-rnn"

mkdir -p $SAVE_ROOT

SE_BNAME="$SUP_MODEL$HIDDEN_SIZE"_"$UCKPT"_FE$UEPOCH
SAVE_PATH="$SAVE_ROOT/$SE_BNAME"
FE_CKPT=$UROOT_PATH/$UCKPT/FE_e"$UEPOCH".ckpt

python -u nnet.py --spk2idx $SPK2IDX --data_root $DATA_ROOT --train_guia $TRAIN_GUIA \
	--log_freq $LOG_FREQ --batch_size $BATCH_SIZE --lr $LR --save_path $SAVE_PATH \
	--model $SUP_MODEL --opt $OPT --patience $PATIENCE --train --lrdec $LRDEC \
	--hidden_size $HIDDEN_SIZE --epoch $EPOCH --sched_mode $SCHED_MODE \
	--fe_cfg ../cfg/frontend_RF160ms_emb100.cfg \
	--fe_ckpt $FE_CKPT

# Now make tests for all supervised epochs
for se in $SEPOCHS; do
	CKPT=$(python select_supervised_ckpt.py $SAVE_PATH $se)
	if [ ! -z "${CKPT##*[!0-9]*}" ] && [ $CKPT -ge 1 ]; then
		echo "File not found for SE $se"
		break
	fi
	LOG_FILE=`basename $CKPT`
	LOG_FILE=${LOG_FILE%.*}
	LOG_FILE=$SAVE_PATH/$LOG_FILE.log
	python -u nnet.py --spk2idx $SPK2IDX --data_root $DATA_ROOT --test_guia $TEST_GUIA \
		--test_ckpt $CKPT --model $SUP_MODEL --hidden_size $HIDDEN_SIZE --test \
		--fe_cfg ../cfg/frontend_RF160ms_emb100.cfg --test_log_file $LOG_FILE
	ACC=$(cat $LOG_FILE | grep "Test accuracy: " | perl -F: -alne 'print $F[1]' | sed 's/^\ //')
	echo -e "$ACC \c" >> $UE_MATRIX_FILE
done
sed -i 's/\ $//' $UE_MATRIX_FILE
echo "" >> $UE_MATRIX_FILE
