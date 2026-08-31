#!/bin/bash
source /root/miniconda3/etc/profile.d/conda.sh
conda activate gromacs
cd /root/collagen

PDB=PLACEHOLDER.pdb
TOP=PLACEHOLDER.top
OUT=/scratch/collagen_sim
mkdir -p $OUT

gmx grompp -f em.mdp  -c $PDB          -p $TOP -o $OUT/em.tpr  && gmx mdrun -v -deffnm $OUT/em
gmx grompp -f nvt.mdp -c $OUT/em.gro   -p $TOP -o $OUT/nvt.tpr && gmx mdrun -v -deffnm $OUT/nvt
gmx grompp -f npt.mdp -c $OUT/nvt.gro  -p $TOP -o $OUT/npt.tpr && gmx mdrun -v -deffnm $OUT/npt
gmx grompp -f md.mdp  -c $OUT/npt.gro  -p $TOP -o $OUT/md.tpr  && gmx mdrun -v -deffnm $OUT/md



gmx mdrun -v -s 1000pN.tpr \
          -deffnm 1000pN \
          -pf pullfx.xvg \
          -px pullx1.xvg \
          -maxh 24 \
          -dlb yes \
          -ntomp 20 \
          -ntmpi 1 \
          -rdd 3.9